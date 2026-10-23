# frozen_string_literal: true

require "zlib"

module Byox
  # Just enough PNG for screenshots: 8-bit RGB or RGBA, not interlaced, which is what
  # headless Chrome writes. Pixels are rows of [r, g, b, a].
  module Png
    SIGNATURE = "\x89PNG\r\n\x1a\n".b
    CHANNELS = { 2 => 3, 6 => 4 }.freeze

    module_function

    def decode(data)
      data = data.b
      raise ArgumentError, "not a PNG" unless data.start_with?(SIGNATURE)

      width = height = depth = color = interlace = nil
      idat = +"".b
      pos = SIGNATURE.size
      while pos < data.size
        len, type = data[pos, 8].unpack("Na4")
        body = data[pos + 8, len]
        case type
        when "IHDR" then width, height, depth, color, _, _, interlace = body.unpack("NNCCCCC")
        when "IDAT" then idat << body
        end
        pos += 12 + len
      end
      channels = CHANNELS[color]
      raise ArgumentError, "unsupported PNG (need 8-bit RGB or RGBA, not interlaced)" unless channels && depth == 8 && interlace.zero?

      unfilter(Zlib::Inflate.inflate(idat), width, height, channels)
    end

    def unfilter(raw, width, height, bpp)
      stride = width * bpp
      prev = Array.new(stride, 0)
      Array.new(height) do |y|
        off = y * (stride + 1)
        filter = raw.getbyte(off)
        line = raw.byteslice(off + 1, stride).bytes
        line.each_index do |i|
          left = i >= bpp ? line[i - bpp] : 0
          up = prev[i]
          upleft = i >= bpp ? prev[i - bpp] : 0
          line[i] = (line[i] + case filter
                               when 0 then 0
                               when 1 then left
                               when 2 then up
                               when 3 then (left + up) / 2
                               when 4 then paeth(left, up, upleft)
                               else raise ArgumentError, "bad PNG filter #{filter}"
                               end) & 0xff
        end
        prev = line
        line.each_slice(bpp).map { |px| bpp == 4 ? px : [*px, 255] }
      end
    end

    def paeth(a, b, c)
      p = a + b - c
      pa, pb, pc = (p - a).abs, (p - b).abs, (p - c).abs
      return a if pa <= pb && pa <= pc

      pb <= pc ? b : c
    end

    def encode(pixels)
      height = pixels.size
      width = pixels.first.size
      raw = pixels.map { |row| "\x00".b + row.flatten.pack("C*") }.join
      chunk = lambda { |type, body|
        [body.bytesize].pack("N") + type + body + [Zlib.crc32(type + body)].pack("N")
      }
      SIGNATURE + chunk.call("IHDR", [width, height, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
        chunk.call("IDAT", Zlib::Deflate.deflate(raw)) + chunk.call("IEND", "")
    end
  end
end
