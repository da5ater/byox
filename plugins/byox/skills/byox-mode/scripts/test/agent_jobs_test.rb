# frozen_string_literal: true

require_relative "helper"

# agent_cmd is a fake script that records its argv, cwd, visible files and env.
class AgentJobsTest < Minitest::Test
  include SiteHelpers

  def setup
    start_site
    @log = File.join(@root, "fake.json")
    ENV["FAKE_LOG"] = @log
    ENV.delete("FAKE_MODE")
  end

  def teardown
    ENV.delete("FAKE_LOG")
    ENV.delete("FAKE_MODE")
    stop_site
  end

  def fake = JSON.parse(File.read(@log))
  def lesson_path = File.join(@app_dir, "course", "lessons", "01-ping.md")

  def test_explain_runs_the_coach_in_a_dir_without_the_solution
    assert_equal 409, sse(api("/steps/01.1/explain"))[0], "explain needs a failing verify first"
    File.write(File.join(@app_dir, "main.rb"), "puts 'PING'\n")
    sse(api("/steps/01.1/verify"))

    out, done = sse(api("/steps/01.1/explain"))
    assert_equal "fake agent ran\n", out
    assert_equal({ "exit" => 0 }, done)

    f = fake
    assert_equal %w[concepts concepts/stdin-loop.md failure.txt learner.diff lesson.md], f["files"]
    refute f["cwd"].start_with?(@root), "the coach must not run inside the course"
    assert_equal "explain", f["env"]["BYOX_JOB"]
    argv = f["argv"]
    assert_match(/\AStep 01\.1 \(Reply to PING\) failed/, argv[0])
    assert_equal File.read(File.join(Byox::PLUGIN_DIR, "agents/coach.md")), argv[argv.index("--append-system-prompt") + 1]
    assert_equal "Read,Glob,Grep", argv[argv.index("--allowedTools") + 1]
    assert_includes argv[argv.index("--disallowedTools") + 1].split(","), "Bash"

    ctx = Dir.mktmpdir
    input = Byox::JobInput.new(course: Fixture.course(@root), config: Fixture.config(@root), lesson: Fixture.course(@root).lesson("01-ping"),
                               step: nil, section: nil, note: nil, failure_path: File.join(@app_dir, "course/.cache/verify/01.1.log"))
    built = Byox::AgentJobs.build_context(input, ctx)
    assert_includes File.read(File.join(built, "failure.txt")), "1 failures"
    assert_includes File.read(File.join(built, "learner.diff")), "+puts 'PING'"
  ensure
    FileUtils.rm_rf(ctx) if ctx
  end

  def test_unclear_keeps_a_rewrite_that_passes_lint
    ENV["FAKE_MODE"] = "rewrite"
    out, done = sse(api("/lessons/01-ping/unclear"), { "section" => "short_read", "note" => "what is a server?" })
    assert_equal "fake agent ran\n", out
    assert_equal({ "exit" => 0, "restored" => false }, done)
    assert_includes File.read(lesson_path), "Redis is a database server"
    assert_includes fake["argv"][0], "what is a server?"
    assert_equal "Read,Edit,Glob,Grep", fake["argv"][fake["argv"].index("--allowedTools") + 1]
  end

  def test_unclear_restores_the_lesson_when_lint_fails
    before = File.read(lesson_path)
    ENV["FAKE_MODE"] = "break"
    out, done = sse(api("/lessons/01-ping/unclear"), { "section" => "task", "note" => "too vague" })
    assert_includes out, "Lint failed, so the lesson was restored."
    assert_equal true, done["restored"]
    assert_equal before, File.read(lesson_path)
    assert_equal 400, sse(api("/lessons/01-ping/unclear"), { "section" => "task" })[0]
  end

  def test_broken_runs_fix_lesson_then_lint_and_strength
    _, done = sse(api("/lessons/02-store/broken"), { "note" => "GET test is flaky" })
    assert_match(%r{\A/byox-mode fix-lesson \S+/mini-redis 02-store\nLearner note: GET test is flaky}, fake["argv"][0])
    assert_equal [], done["findings"]
    assert_equal ["02.1\t1\t0\tok", "02.2\t1\t0\tok"], done["strength"]
    state = JSON.parse(File.read(File.join(@app_dir, "course", "state.json")))
    assert_equal [%w[broken 02-store]], state["feedback"].map { _1.values_at("kind", "lesson") }
  end

  def test_one_agent_job_per_course_at_a_time
    ENV["FAKE_MODE"] = "sleep"
    first = Thread.new { sse(api("/lessons/01-ping/broken"), { "note" => "x" }) }
    sleep 0.4
    code, body = sse(api("/lessons/01-ping/unclear"), { "section" => "task", "note" => "y" })
    assert_equal [409, "an agent job is already running for this course"], [code, body["error"]]
    first.join
  end
end
