# frozen_string_literal: true

module Byox
  # Visual checks for frontend steps: a screenshot tool and a pixel diff, so a design
  # target can be a plain PNG with no design software involved.
  module Visual
    CHROMES = %w[google-chrome google-chrome-stable chromium chromium-browser chrome].freeze
    # A channel must move by more than this before a pixel counts as different, which
    # ignores anti-aliasing and font smoothing noise.
    CHANNEL_DELTA = 16

    Result = Data.define(:ratio, :differing, :total, :width, :height)

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

    def diff(target_path, actual_path, out: nil)
      target = Png.decode(File.binread(target_path))
      actual = Png.decode(File.binread(actual_path))
      sizes = [target, actual].map { "#{_1.first.size}x#{_1.size}" }
      raise SizeMismatch, "the page is #{sizes[1]} but the target is #{sizes[0]}" unless sizes.uniq.size == 1

      differing = 0
      painted = target.each_with_index.map do |row, y|
        row.each_with_index.map do |t, x|
          if t.first(3).zip(actual[y][x].first(3)).any? { |a, b| (a - b).abs > CHANNEL_DELTA }
            differing += 1
            [255, 0, 0, 255]
          else
            [t[0] / 3 + 170, t[1] / 3 + 170, t[2] / 3 + 170, 255]
          end
        end
      end
      File.binwrite(out, Png.encode(painted)) if out
      total = target.size * target.first.size
      Result.new(ratio: differing.to_f / total, differing:, total:, width: target.first.size, height: target.size)
    end

    class SizeMismatch < ArgumentError; end
  end
end
