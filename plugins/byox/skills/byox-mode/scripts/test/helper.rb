# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "byox"
require "minitest/autorun"
require "net/http"
require_relative "fixtures/make_mini_redis"

module Fixture
  FAKE_AGENT = <<~RUBY
    require "json"
    File.write(ENV.fetch("FAKE_LOG"), JSON.generate({ "argv" => ARGV, "cwd" => Dir.pwd, "files" => Dir["**/*"].sort,
                                                      "env" => ENV.to_h.slice("BYOX_JOB", "BYOX_TARGET", "BYOX_COURSE") }))
    puts "fake agent ran"
    target = ENV["BYOX_TARGET"]
    case ENV["FAKE_MODE"]
    when "break" then File.write(target, "not a lesson")
    when "rewrite" then File.write(target, File.read(target).sub("Redis is a server", "Redis is a database server").sub("A loop reads", "A loop waits for and reads"))
    when "sleep" then sleep 1.5
    end
  RUBY

  module_function

  def build(agent_cmd: nil)
    root = Dir.mktmpdir("byox-test-")
    fake = File.join(root, "fake_agent.rb")
    File.write(fake, FAKE_AGENT)
    MiniRedis.build(root, agent_cmd: agent_cmd || "ruby #{fake}")
    root
  end

  def course(root) = Byox::Course.load(File.join(root, "mini-redis"))
  def config(root) = Byox::Config.load(root)
  def solution_code(step) = MiniRedis::SOLUTION.fetch(step)

  def edit_lesson(root, id)
    path = File.join(root, "mini-redis", "course", "lessons", "#{id}.md")
    File.write(path, yield(File.read(path)))
  end
end

module SiteHelpers
  def start_site(agent_cmd: nil)
    @root = Fixture.build(agent_cmd:)
    @site = Byox::Site.start(Fixture.config(@root), port: 0)
    @app_dir = File.join(@root, "mini-redis")
  end

  def stop_site
    @site&.stop
    FileUtils.rm_rf(@root)
  end

  def http(verb, path, body = nil)
    Net::HTTP.start("127.0.0.1", @site.port, read_timeout: 30) do |h|
      req = verb == :get ? Net::HTTP::Get.new(path) : Net::HTTP::Post.new(path, "Content-Type" => "application/json")
      req.body = JSON.generate(body) if body
      res = h.request(req)
      [res.code.to_i, res["content-type"], res.body]
    end
  end

  def json(verb, path, body = nil)
    code, _type, raw = http(verb, path, body)
    [code, JSON.parse(raw)]
  end

  # Returns [lines, done] from an SSE response.
  def sse(path, body = nil)
    code, type, raw = http(:post, path, body)
    return [code, JSON.parse(raw)] unless type == "text/event-stream"

    events = raw.split("\n\n").map { |f| [f[/^event: (.*)$/, 1], JSON.parse(f[/^data: (.*)$/, 1])] }
    [events.select { _1[0] == "line" }.map { _1[1]["text"] }.join, events.find { _1[0] == "done" }&.last]
  end

  def learner_writes(step) = File.write(File.join(@app_dir, "main.rb"), Fixture.solution_code(step))
  def api(path) = "/api/courses/mini-redis#{path}"
end
