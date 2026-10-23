# frozen_string_literal: true

module Byox
  # Visual checks for frontend steps: a screenshot tool and a pixel diff, so a design
  # target can be a plain PNG with no design software involved.
  module Visual
    CHROMES = %w[google-chrome google-chrome-stable chromium chromium-browser chrome].freeze
    # A channel must move by more than this before a pixel counts as different, which
    # ignores anti-aliasing and font smoothing noise.
    CHANNEL_DELTA = 16

    Result = Data.define(:ratio, :differing, :total, :width, :height, :block)

    module_function

    def chrome
      return ENV["BYOX_CHROME"] if ENV["BYOX_CHROME"] && File.executable?(ENV["BYOX_CHROME"])

      found = CHROMES.filter_map { |n| ENV["PATH"].to_s.split(":").map { File.join(_1, n) }.find { |p| File.executable?(p) } }.first
      found || Dir[File.expand_path("~/.cache/ms-playwright/chromium-*/chrome-linux*/chrome")].max
    end

    def shot(url, out, width: 1280, height: 800, wait_ms: 3000)
      bin = chrome or raise ArgumentError, "no Chrome or Chromium found. Install one, or set BYOX_CHROME to its path."
      Dir.mktmpdir("byox-chrome-") do |profile|
        code, output = Shell.capture(["timeout", "60", bin, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                                      "--user-data-dir=#{profile}", "--window-size=#{width},#{height}",
                                      "--virtual-time-budget=#{wait_ms}", "--screenshot=#{File.expand_path(out)}", url], cwd: Dir.pwd)
        raise ArgumentError, "Chrome could not capture #{url}: #{output.lines.last(3).join.strip}" unless code.zero? && File.exist?(out)
      end
    end

    # block 1 compares every pixel. A bigger block compares the average color of each
    # block x block square instead, which ignores font smoothing and one pixel shifts but
    # still catches a wrong color, a missing element or a layout that moved.
    def diff(target_path, actual_path, out: nil, block: 1)
      target = Png.decode(File.binread(target_path))
      actual = Png.decode(File.binread(actual_path))
      sizes = [target, actual].map { "#{_1.first.size}x#{_1.size}" }
      raise SizeMismatch, "the page is #{sizes[1]} but the target is #{sizes[0]}" unless sizes.uniq.size == 1

      height = target.size
      width = target.first.size
      block = [block.to_i, 1].max
      differing = 0
      total = 0
      flagged = Array.new(height) { Array.new(width, false) }
      (0...height).step(block) do |y0|
        (0...width).step(block) do |x0|
          cells = (y0...[y0 + block, height].min).flat_map { |y| (x0...[x0 + block, width].min).map { |x| [y, x] } }
          t = average(cells.map { |y, x| target[y][x] })
          a = average(cells.map { |y, x| actual[y][x] })
          total += 1
          next unless t.zip(a).any? { |p, q| (p - q).abs > CHANNEL_DELTA }

          differing += 1
          cells.each { |y, x| flagged[y][x] = true }
        end
      end
      write_diff(out, target, flagged) if out
      Result.new(ratio: differing.to_f / total, differing:, total:, width:, height:, block:)
    end

    def average(pixels)
      sums = pixels.each_with_object([0, 0, 0]) { |px, acc| 3.times { |i| acc[i] += px[i] } }
      sums.map { _1 / pixels.size }
    end

    def write_diff(path, target, flagged)
      painted = target.each_with_index.map do |row, y|
        row.each_with_index.map { |t, x| flagged[y][x] ? [255, 0, 0, 255] : [t[0] / 3 + 170, t[1] / 3 + 170, t[2] / 3 + 170, 255] }
      end
      File.binwrite(path, Png.encode(painted))
    end

    class SizeMismatch < ArgumentError; end
  end
end
