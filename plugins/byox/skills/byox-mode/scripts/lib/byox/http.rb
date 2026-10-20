# frozen_string_literal: true

require "socket"
require "uri"

# A minimal HTTP/1.1 server on TCPServer: one thread per connection, Connection: close,
# JSON bodies, and Server-Sent Events for streams. WEBrick left the standard library
# in Ruby 3.0, and the site must start with no install step.
module Byox
  module Http
    Request = Data.define(:method, :path, :query, :body)
    Response = Data.define(:status, :type, :body)
    Sse = Data.define(:producer) # producer.call(emit), emit.(event, data)

    REASONS = { 200 => "OK", 400 => "Bad Request", 403 => "Forbidden", 404 => "Not Found",
                409 => "Conflict", 500 => "Internal Server Error" }.freeze

    module_function

    def json(status, obj) = Response.new(status, "application/json", JSON.generate(obj))

    def serve(server, &handler)
      loop do
        sock = server.accept
        Thread.new(sock) { handle(_1, &handler) }
      rescue IOError, Errno::EBADF
        break
      end
    end

    def handle(sock)
      req = read_request(sock) or return
      res = begin
        yield req
      rescue StandardError => e
        json(500, { "error" => "#{e.class}: #{e.message}" })
      end
      res.is_a?(Sse) ? write_sse(sock, res) : write(sock, res)
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError
      nil
    ensure
      sock.close unless sock.closed?
    end

    def read_request(sock)
      line = sock.gets or return
      method, target = line.split(" ", 3)
      headers = {}
      while (h = sock.gets) && h != "\r\n"
        k, v = h.split(":", 2)
        headers[k.strip.downcase] = v.to_s.strip
      end
      raw = headers["content-length"] ? sock.read(headers["content-length"].to_i) : ""
      path, q = target.to_s.split("?", 2)
      body = raw.to_s.empty? ? {} : JSON.parse(raw)
      Request.new(method:, path:, query: URI.decode_www_form(q.to_s).to_h, body: body.is_a?(Hash) ? body : {})
    rescue JSON::ParserError
      Request.new(method:, path:, query: {}, body: {})
    end

    def write(sock, res)
      sock.write("HTTP/1.1 #{res.status} #{REASONS.fetch(res.status, 'OK')}\r\nContent-Type: #{res.type}\r\n" \
                 "Content-Length: #{res.body.bytesize}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")
      sock.write(res.body)
    end

    def write_sse(sock, sse)
      sock.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")
      # A closed tab must not abort the producer, or a finished verify would never be recorded.
      emit = lambda do |event, data|
        sock.write("event: #{event}\ndata: #{JSON.generate(data)}\n\n")
      rescue Errno::EPIPE, Errno::ECONNRESET, IOError
        nil
      end
      sse.producer.call(emit)
    end
  end
end
