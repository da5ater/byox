# frozen_string_literal: true

require_relative "helper"

class FeedbackTest < Minitest::Test
  include SiteHelpers

  def setup
    @root = Fixture.build
    @repo = File.join(@root, "plugin-repo")
    FileUtils.mkdir_p(@repo)
    File.open(File.join(@root, "byox.yml"), "a") { _1.puts("plugin_repo: #{@repo}") }
    @log = File.join(@root, "fake.json")
    ENV["FAKE_LOG"] = @log
    @site = Byox::Site.start(Fixture.config(@root), port: 0)
  end

  def teardown
    ENV.delete("FAKE_LOG")
    stop_site
  end

  def byox(*args)
    out, status = Open3.capture2e(File.expand_path("../byox", __dir__), *args, "--root", @root)
    [status.exitstatus, out]
  end

  def test_the_cli_adds_lists_and_marks_feedback
    assert_equal 0, byox("feedback", "add", "The Verify button is too small on a phone", "--page", "#/c/mini-redis/01-ping")[0]
    assert_equal 0, byox("feedback", "add", "Hints should show which one I am on")[0]
    _, open = byox("feedback", "list", "--open")
    rows = open.lines.drop(1).map { _1.chomp.split("\t") }
    assert_equal 2, rows.size
    assert_equal ["open", "#/c/mini-redis/01-ping", "The Verify button is too small on a phone"], rows[0][1..3]

    assert_equal 0, byox("feedback", "mark", rows[0][0], "--pr", "https://github.com/o/r/pull/1")[0]
    _, still_open = byox("feedback", "list", "--open")
    assert_equal ["Hints should show which one I am on"], still_open.lines.drop(1).map { _1.chomp.split("\t")[3] }
    _, all = byox("feedback", "list")
    assert_includes all, "in_pr\t#/c/mini-redis/01-ping\tThe Verify button is too small on a phone\thttps://github.com/o/r/pull/1"
    assert_equal 2, byox("feedback", "add", "  ")[0], "empty feedback is bad input"
  end

  def test_the_site_saves_feedback_with_the_page_it_came_from
    assert_equal 400, json(:post, "/api/feedback", { "text" => " ", "page" => "#/" })[0]
    code, body = json(:post, "/api/feedback", { "text" => "Make the course map bigger", "page" => "#/c/mini-redis" })
    assert_equal [200, 1], [code, body["open"]]
    assert_equal "#/c/mini-redis", body["item"]["page"]
    _, listed = json(:get, "/api/feedback")
    assert_equal ["Make the course map bigger"], listed["items"].map { _1["text"] }
  end

  def test_ship_runs_the_feedback_agent_in_the_plugin_repo
    assert_equal 409, json(:post, "/api/feedback/ship")[0], "nothing to ship yet"
    json(:post, "/api/feedback", { "text" => "Make the course map bigger", "page" => "#/c/mini-redis" })

    out, done = sse("/api/feedback/ship")
    assert_equal "fake agent ran\n", out
    assert_equal 0, done["exit"]
    f = JSON.parse(File.read(@log))
    assert_equal File.realpath(@repo), File.realpath(f["cwd"])
    assert_equal "feedback", f["env"]["BYOX_JOB"]
    argv = f["argv"]
    assert_match(/Ship mode/, argv[0])
    assert_includes argv[0], File.join(@root, ".byox", "feedback.jsonl")
    assert_equal File.read(File.join(Byox::PLUGIN_DIR, "agents/feedback.md")), argv[argv.index("--append-system-prompt") + 1]
    assert_includes argv[argv.index("--allowedTools") + 1].split(","), "Bash"
  end
end

class FeedbackDefaultsTest < Minitest::Test
  def test_a_fresh_root_has_portable_defaults_and_ships_through_upstream
    root = Dir.mktmpdir("byox-fresh-")
    config = Byox::Config.load(root)
    assert_equal File.join(root, "vault"), config.vault
    assert_nil config.plugin_repo
    assert_equal "da5ater/byox", config.upstream

    input = Byox::JobInput.new(course: nil, config:, lesson: nil, step: nil, section: nil, note: nil, failure_path: nil, target: nil)
    prompt = Byox::AGENT_JOBS[:feedback].prompt.call(input)
    assert_includes prompt, "da5ater/byox"
    assert_includes prompt, "no local byox checkout"
  ensure
    FileUtils.rm_rf(root)
  end

  def test_the_default_root_is_byox_courses_in_home
    ENV.delete("BYOX_ROOT")
    assert_equal File.expand_path("~/byox-courses"), Byox::Config.load.root
  end
end

class FeedbackUploadTest < Minitest::Test
  include SiteHelpers

  def setup
    @root = Fixture.build
    @repo = File.join(@root, "plugin-repo")
    FileUtils.mkdir_p(@repo)
    system("git", "-C", @repo, "init", "-q", "-b", "main")
    File.write(File.join(@repo, "app.css"), "body { color: red; }\n")
    system("git", "-C", @repo, "add", "-A")
    system("git", "-C", @repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
    File.open(File.join(@root, "byox.yml"), "a") { _1.puts("plugin_repo: #{@repo}") }
    @log = File.join(@root, "fake.json")
    ENV["FAKE_LOG"] = @log
    @site = Byox::Site.start(Fixture.config(@root), port: 0)
  end

  def teardown
    ENV.delete("FAKE_LOG")
    stop_site
  end

  def test_upload_packages_the_learners_own_changes
    _, before = json(:get, "/api/feedback")
    assert_equal 0, before["changes"]
    assert_equal 409, json(:post, "/api/feedback/upload")[0], "nothing changed yet"

    File.write(File.join(@repo, "app.css"), "body { color: blue; }\n")
    File.write(File.join(@repo, "new.js"), "console.log(1)\n")
    _, after = json(:get, "/api/feedback")
    assert_equal 2, after["changes"]

    out, done = sse("/api/feedback/upload")
    assert_equal ["fake agent ran\n", 0], [out, done["exit"]]
    f = JSON.parse(File.read(@log))
    assert_equal File.realpath(@repo), File.realpath(f["cwd"])
    assert_match(/Upload mode/, f["argv"][0])
    assert_includes f["argv"][0], "feedback-upload.md"
  end
end

class FeedbackUploadWithoutRepoTest < Minitest::Test
  include SiteHelpers

  def setup = start_site
  def teardown = stop_site

  def test_upload_needs_a_local_checkout
    _, body = json(:get, "/api/feedback")
    assert_nil body["changes"]
    code, err = json(:post, "/api/feedback/upload")
    assert_equal 409, code
    assert_match(/plugin_repo/, err["error"])
  end
end

class AddLessonsTest < Minitest::Test
  include SiteHelpers

  def setup
    start_site
    @log = File.join(@root, "fake.json")
    ENV["FAKE_LOG"] = @log
  end

  def teardown
    ENV.delete("FAKE_LOG")
    stop_site
  end

  def test_the_site_asks_the_agent_to_add_lessons_to_a_course
    assert_equal 400, json(:post, api("/add-lessons"), { "request" => "  " })[0]
    request = "Add the next 5 lectures of the transcript at ~/Downloads/more.txt"
    out, done = sse(api("/add-lessons"), { "request" => request })
    assert_equal ["fake agent ran\n", 0], [out, done["exit"]]
    f = JSON.parse(File.read(@log))
    assert_equal File.realpath(@app_dir), File.realpath(f["cwd"])
    assert_equal "add_lessons", f["env"]["BYOX_JOB"]
    prompt = f["argv"][0]
    assert_includes prompt, request
    assert_includes prompt, "add-lessons.md"
    assert_includes prompt, @app_dir
    assert_includes f["argv"][f["argv"].index("--allowedTools") + 1].split(","), "Agent"
  end

  def test_an_unknown_course_is_not_found
    assert_equal 404, json(:post, "/api/courses/nope/add-lessons", { "request" => "more" })[0]
  end
end
