# frozen_string_literal: true

require_relative "helper"

class VisualTest < Minitest::Test
  def setup = @dir = Dir.mktmpdir("byox-visual-")
  def teardown = FileUtils.rm_rf(@dir)

  def byox(*args)
    out, status = Open3.capture2e(File.expand_path("../byox", __dir__), *args)
    [status.exitstatus, out]
  end

  def png(name, width: 40, height: 20, square: nil)
    pixels = Array.new(height) { Array.new(width) { [255, 255, 255, 255] } }
    if square
      x, y, size, color = square
      size.times { |dy| size.times { |dx| pixels[y + dy][x + dx] = color } }
    end
    path = File.join(@dir, name)
    File.binwrite(path, Byox::Png.encode(pixels))
    path
  end

  def test_png_round_trips
    pixels = [[[1, 2, 3, 255], [250, 251, 252, 255]], [[0, 0, 0, 255], [255, 255, 255, 255]]]
    assert_equal pixels, Byox::Png.decode(Byox::Png.encode(pixels))
  end

  def test_identical_images_pass
    a = png("a.png")
    code, out = byox("visual-diff", a, png("b.png"))
    assert_equal 0, code
    assert_match(/0\.00% of pixels differ/, out)
  end

  def test_a_small_difference_is_inside_the_tolerance
    target = png("t.png")
    actual = png("a.png", square: [2, 2, 4, [0, 0, 255, 255]]) # 16 of 800 pixels, 2%
    code, out = byox("visual-diff", target, actual, "--tolerance", "0.03")
    assert_equal 0, code, out
    assert_match(/2\.00% of pixels differ \(limit 3\.00%\)/, out)
  end

  def test_a_bigger_difference_fails_and_writes_a_diff_image
    target = png("t.png")
    actual = png("a.png", square: [0, 0, 10, [255, 0, 0, 255]]) # 100 of 800, 12.5%
    out_path = File.join(@dir, "diff.png")
    code, out = byox("visual-diff", target, actual, "--tolerance", "0.02", "--out", out_path)
    assert_equal 1, code
    assert_match(/12\.50% of pixels differ \(limit 2\.00%\)/, out)
    diff = Byox::Png.decode(File.binread(out_path))
    assert_equal [40, 20], [diff[0].size, diff.size]
    assert_equal [255, 0, 0], diff[0][0][0, 3], "differing pixels are painted red"
  end

  def test_a_tiny_color_shift_below_the_channel_threshold_is_ignored
    target = png("t.png")
    actual = png("a.png", square: [0, 0, 20, [250, 250, 250, 255]]) # anti-aliasing sized noise
    assert_equal 0, byox("visual-diff", target, actual)[0]
  end

  def test_different_sizes_fail_with_both_sizes_named
    code, out = byox("visual-diff", png("t.png", width: 40), png("a.png", width: 41))
    assert_equal 1, code
    assert_includes out, "40x20"
    assert_includes out, "41x20"
  end

  def test_a_missing_file_is_bad_input
    assert_equal 2, byox("visual-diff", File.join(@dir, "nope.png"), png("a.png"))[0]
  end

  def test_shot_captures_a_page_at_the_requested_size
    skip "no Chrome or Chromium found" unless Byox::Visual.chrome
    html = File.join(@dir, "page.html")
    File.write(html, "<body style='margin:0;background:#0a0'><h1>byox</h1></body>")
    out = File.join(@dir, "shot.png")
    code, msg = byox("shot", "file://#{html}", out, "--size", "320x200")
    assert_equal 0, code, msg
    pixels = Byox::Png.decode(File.binread(out))
    assert_equal [320, 200], [pixels[0].size, pixels.size]
    assert_equal [0, 170, 0], pixels[150][300][0, 3], "the page background reaches the bottom right corner"
  end
end

class VisualSiteTest < Minitest::Test
  include SiteHelpers

  def setup = start_site
  def teardown = stop_site

  def set_kind(step, kind)
    Fixture.edit_lesson(@root, "01-ping") { |t| t.sub(/(- id: ["']?#{Regexp.escape(step)}["']?\n\s*title: [^\n]*\n\s*kind: )\w+/) { "#{$1}#{kind}" } }
  end

  def test_a_visual_step_shows_its_target_and_the_last_diff
    set_kind("01.1", "visual")
    _, body = json(:get, api("/lessons/01-ping"))
    assert_nil body["steps"][0]["design"], "no target file yet"

    FileUtils.mkdir_p(File.join(@app_dir, "course/tests/01.1"))
    File.binwrite(File.join(@app_dir, "course/tests/01.1/target.png"), Byox::Png.encode([[[0, 0, 0, 255]]]))
    _, body = json(:get, api("/lessons/01-ping"))
    assert_equal api("/files/course/tests/01.1/target.png"), body["steps"][0]["design"]
    assert_nil body["steps"][0]["diff"]

    FileUtils.mkdir_p(File.join(@app_dir, "course/.cache"))
    File.binwrite(File.join(@app_dir, "course/.cache/diff-01.1.png"), Byox::Png.encode([[[255, 0, 0, 255]]]))
    _, body = json(:get, api("/lessons/01-ping"))
    assert_equal api("/files/course/.cache/diff-01.1.png"), body["steps"][0]["diff"]

    assert_nil body["steps"][0]["design_phone"]
    assert_nil body["steps"][0]["design_source"]
    File.binwrite(File.join(@app_dir, "course/tests/01.1/target-phone.png"), Byox::Png.encode([[[9, 9, 9, 255]]]))
    FileUtils.mkdir_p(File.join(@app_dir, "course/design/01.1"))
    File.write(File.join(@app_dir, "course/design/01.1/design.html"), "<h1>design</h1>")
    _, body = json(:get, api("/lessons/01-ping"))
    assert_equal api("/files/course/tests/01.1/target-phone.png"), body["steps"][0]["design_phone"]
    assert_equal "course/design/01.1/design.html", body["steps"][0]["design_source"], "the learner opens the design file from disk"
    assert_equal 404, http(:get, api("/files/course/design/01.1/design.html"))[0], "agent-written HTML is never served from the site's origin"

    code, type, raw = http(:get, api("/files/course/tests/01.1/target.png"))
    assert_equal [200, "image/png"], [code, type]
    assert_equal [[[0, 0, 0, 255]]], Byox::Png.decode(raw)
  end

  def test_only_design_images_are_served
    ["/files/course/course.md", "/files/course/solution/main.rb", "/files/course/state.json",
     "/files/course/tests/01.1/../../course.md", "/files/..%2Fbyox.yml"].each do |p|
      assert_equal 404, http(:get, api(p))[0], "#{p} must not be served"
    end
    FileUtils.mkdir_p(File.join(@app_dir, "course/design"))
    File.binwrite(File.join(@app_dir, "course/design/home.png"), Byox::Png.encode([[[1, 2, 3, 255]]]))
    assert_equal 200, http(:get, api("/files/course/design/home.png"))[0]
  end

  def test_verify_scripts_can_find_byox_and_the_step
    File.write(File.join(@app_dir, "course/verify/01.1.sh"), "#!/bin/sh\necho \"$BYOX_BIN $BYOX_STEP\"\nexit 1\n")
    out, = sse(api("/steps/01.1/verify"))
    assert_equal "#{Byox::BIN} 01.1\n", out
    assert File.executable?(Byox::BIN)
  end

  def test_a_lesson_still_being_written_is_held_back
    Fixture.edit_lesson(@root, "01-ping") { _1 } # lesson file exists
    course_md = File.join(@app_dir, "course/course.md")
    File.write(course_md, File.read(course_md).sub(/(- id: 02-store\n)/, "\\1    building: true\n"))
    _, map = json(:get, api(""))
    store = map["lessons"].find { _1["id"] == "02-store" }
    assert_equal "building", store["status"]
    learn(%w[01.1 01.2])
    _, map = json(:get, api(""))
    assert_equal "building", map["lessons"].find { _1["id"] == "02-store" }["status"], "still held back after lesson 1 is green"
    code, body = json(:get, api("/lessons/02-store"))
    assert_equal [403, "building"], [code, body["status"]]
  end

  def learn(steps)
    steps.each do |s|
      learner_writes(s)
      sse(api("/steps/#{s}/verify"))
    end
  end
end
