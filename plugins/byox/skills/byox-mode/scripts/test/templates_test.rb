# frozen_string_literal: true

require_relative "helper"
require "socket"

class TemplatesTest < Minitest::Test
  TEMPLATES = File.expand_path("../../references/templates", __dir__)

  def setup = @dir = Dir.mktmpdir("byox-templates-")
  def teardown = FileUtils.rm_rf(@dir)

  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1].tap { server.close }
  end

  def run_script(name, env = {}, chdir: @dir)
    Open3.capture2e({ "BYOX_BIN" => Byox::BIN, "BYOX_STEP" => "04.1" }.merge(env), "sh", File.join(TEMPLATES, name), chdir:)
  end

  def page(color)
    "<body style='margin:0;background:#{color}'><h1 style='color:#fff;padding:40px'>Corsego</h1></body>"
  end

  def test_the_visual_template_goes_green_on_the_design_and_red_with_a_diff_image_when_the_page_drifts
    skip "needs Chrome and python3" unless Byox::Visual.chrome && system("python3", "--version", out: File::NULL)

    # The agent's side: a design file, rendered to the target the learner is given.
    FileUtils.mkdir_p(File.join(@dir, "course/design/04.1"))
    FileUtils.mkdir_p(File.join(@dir, "course/tests/04.1"))
    File.write(File.join(@dir, "course/design/04.1/design.html"), page("#1b2430"))
    Byox::Visual.shot("file://#{@dir}/course/design/04.1/design.html", File.join(@dir, "course/tests/04.1/target.png"), width: 1280, height: 800)

    # The learner's side: an app that serves the page.
    FileUtils.mkdir_p(File.join(@dir, "site"))
    File.write(File.join(@dir, "site/index.html"), page("#1b2430"))
    port = free_port
    env = { "START_CMD" => "python3 -m http.server #{port} --bind 127.0.0.1 --directory site", "URL" => "http://127.0.0.1:#{port}/" }

    out, status = run_script("verify-visual.sh", env)
    assert status.success?, out
    assert_match(/Desktop, 1280x800:\n0\.00% of pixels differ/, out)

    File.write(File.join(@dir, "site/index.html"), page("#c8553d"))
    out, status = run_script("verify-visual.sh", env)
    refute status.success?
    assert_match(/Desktop, 1280x800:\n\d+\.\d+% of pixels differ \(limit 3\.00%\)/, out)
    assert_includes out, "course/.cache/diff-04.1.png"
    diff = Byox::Png.decode(File.binread(File.join(@dir, "course/.cache/diff-04.1.png")))
    assert_equal [1280, 800], [diff[0].size, diff.size]
    assert_equal [255, 0, 0], diff[400][600][0, 3]
    assert_nil `lsof -ti tcp:#{port} 2>/dev/null`.strip.then { _1.empty? ? nil : _1 }, "the template must stop the server it started"
  end

  def test_the_visual_template_works_from_a_work_folder_through_byox_course
    skip "needs Chrome and python3" unless Byox::Visual.chrome && system("python3", "--version", out: File::NULL)

    FileUtils.mkdir_p(File.join(@dir, "course/tests/04.1"))
    FileUtils.mkdir_p(File.join(@dir, "work/site"))
    File.write(File.join(@dir, "work/site/index.html"), page("#1b2430"))
    Byox::Visual.shot("file://#{@dir}/work/site/index.html", File.join(@dir, "course/tests/04.1/target.png"), width: 1280, height: 800)
    port = free_port
    env = { "BYOX_COURSE" => File.join(@dir, "course"), "START_CMD" => "python3 -m http.server #{port} --bind 127.0.0.1 --directory site",
            "URL" => "http://127.0.0.1:#{port}/" }

    out, status = run_script("verify-visual.sh", env, chdir: File.join(@dir, "work"))
    assert status.success?, out
    assert File.file?(File.join(@dir, "course/.cache/actual-04.1.png")), "screenshots go in the course folder"
    assert_equal ["site"], Dir.children(File.join(@dir, "work")), "the learner's folder gets no cache files"
  end

  def test_the_visual_template_says_so_when_the_app_never_answers
    FileUtils.mkdir_p(File.join(@dir, "course/tests/04.1"))
    out, status = run_script("verify-visual.sh", { "START_CMD" => "sleep 60", "URL" => "http://127.0.0.1:#{free_port}/" })
    refute status.success?
    assert_match(/Your app did not answer at http:\/\/127\.0\.0\.1:\d+\/ after 30 seconds/, out)
  end

  def fake_aws(buckets: [], versioning: "None")
    bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(bin)
    path = File.join(bin, "aws")
    File.write(path, <<~SH)
      #!/bin/sh
      case "$*" in
        *head-bucket*) case " #{buckets.join(' ')} " in *" corsego-uploads "*) exit 0;; *) echo "An error occurred (404) when calling the HeadBucket operation: Not Found" >&2; exit 254;; esac ;;
        *get-bucket-versioning*) echo "#{versioning}" ;;
      esac
    SH
    File.chmod(0o755, path)
    { "PATH" => "#{bin}:#{ENV['PATH']}" }
  end

  def test_the_cloud_template_passes_when_the_cli_says_the_setup_is_right
    out, status = run_script("verify-cloud.sh", fake_aws(buckets: ["corsego-uploads"], versioning: "Enabled"))
    assert status.success?, out
    assert_includes out, "ok   the bucket corsego-uploads exists"
    assert_includes out, "ok   versioning is enabled on the bucket"
    assert_includes out, "All checks passed."
  end

  def test_the_cloud_template_stops_at_the_first_wrong_answer_and_says_what_it_saw
    out, status = run_script("verify-cloud.sh", fake_aws(buckets: ["corsego-uploads"], versioning: "Suspended"))
    refute status.success?
    assert_includes out, "ok   the bucket corsego-uploads exists"
    assert_includes out, "FAIL versioning is enabled on the bucket"
    assert_includes out, "expected: Enabled"
    assert_includes out, "got:      Suspended"
    refute_includes out, "All checks passed."
  end

  def test_the_cloud_template_shows_the_cli_error_when_a_command_fails
    out, status = run_script("verify-cloud.sh", fake_aws(buckets: []))
    refute status.success?
    assert_includes out, "FAIL the bucket corsego-uploads exists"
    assert_includes out, "command: aws s3api head-bucket --bucket corsego-uploads"
    assert_includes out, "HeadBucket operation: Not Found"
  end
end
