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
    denied = argv[argv.index("--disallowedTools") + 1].split(",")
    assert_includes denied, "Bash"
    %w[solution source].each do |dir|
      assert_includes denied, "Read(/#{File.join(@app_dir, 'course', dir)}/**)", "an absolute path must not reach course/#{dir}"
    end
    hint = Fixture.course(@root).lesson("01-ping").steps.first.hints.first
    refute_includes f["lesson"], hint, "unrevealed hints must not reach the coach"

    ctx = Dir.mktmpdir
    input = Byox::JobInput.new(course: Fixture.course(@root), config: Fixture.config(@root), lesson: Fixture.course(@root).lesson("01-ping"),
                               step: nil, section: nil, note: nil, failure_path: File.join(@app_dir, "course/.cache/verify/01.1.log"),
                               target: nil)
    built = Byox::AgentJobs.build_context(input, ctx)
    assert_includes File.read(File.join(built, "failure.txt")), "1 failures"
    assert_includes File.read(File.join(built, "learner.diff")), "+puts 'PING'"
  ensure
    FileUtils.rm_rf(ctx) if ctx
  end

  def test_help_interview_asks_then_diagnoses_in_a_dir_without_the_solution
    path = "/steps/01.1/help/interview"
    assert_equal 400, json(:post, api(path), { "selection" => "", "messages" => [{ "role" => "learner", "text" => "x" }] })[0], "needs a selection"
    assert_equal 400, json(:post, api(path), { "selection" => "a loop", "messages" => [] })[0], "needs the learner's problem"
    ENV["FAKE_MODE"] = "help_ask"
    out, done = sse(api(path), { "selection" => "a loop reads", "messages" => [{ "role" => "learner", "text" => "I do not know how" }] })
    assert_includes out, "BYOX_JSON"
    assert_equal "ask", done["reply"]["type"]
    f = fake
    assert_equal "help_interview", f["env"]["BYOX_JOB"]
    assert_includes f["argv"][0], "a loop reads"
    assert_includes f["argv"][0], "Learner: I do not know how"
    assert_equal File.read(File.join(Byox::PLUGIN_DIR, "agents/helper.md")), f["argv"][f["argv"].index("--append-system-prompt") + 1]
    denied = f["argv"][f["argv"].index("--disallowedTools") + 1].split(",")
    assert_includes denied, "Read(/#{File.join(@app_dir, 'course', 'solution')}/**)"
    refute_includes f["argv"][f["argv"].index("--allowedTools") + 1], "Write"

    ENV["FAKE_MODE"] = "help_diagnosis"
    _, done = sse(api(path), { "selection" => "a loop", "messages" => [{ "role" => "learner", "text" => "x" }] })
    assert_equal "reading in a loop", done["reply"]["gaps"][0]["gap"]
  end

  def test_help_hard_saves_clean_resources_under_the_step
    ENV["FAKE_MODE"] = "help_hard"
    gaps = [{ "id" => "g1", "gap" => "reading in a loop", "detail" => "d" }]
    assert_equal 400, json(:post, api("/steps/01.1/help/hard"), { "selection" => "a loop" })[0], "needs the diagnosis"
    _, done = sse(api("/steps/01.1/help/hard"), { "selection" => "a loop", "messages" => [{ "role" => "learner", "text" => "x" }], "gaps" => gaps })
    assert_equal 2, done["saved"], "the javascript: url is dropped"
    assert_includes fake["argv"][fake["argv"].index("--allowedTools") + 1], "WebSearch"
    step = json(:get, api("/lessons/01-ping"))[1]["steps"][0]
    assert_equal ["tutorial", "gap"], step["help"].map { _1["kind"] }
    assert_equal "reading in a loop", step["help"][1]["gap"]
  end

  def test_help_easy_saves_the_printed_tutorial
    ENV["FAKE_MODE"] = "help_easy"
    gaps = [{ "id" => "g1", "gap" => "reading in a loop", "detail" => "d" }]
    _, done = sse(api("/steps/01.1/help/easy"), { "selection" => "a loop", "messages" => [], "gaps" => gaps })
    assert_equal 1, done["saved"]
    assert_equal File.read(File.join(Byox::PLUGIN_DIR, "skills/byox-teach/SKILL.md")), fake["argv"][fake["argv"].index("--append-system-prompt") + 1]
    item = Byox::Help.load(Fixture.course(@root), "01.1")[0]
    assert_equal "Loops by building a counter", item["title"]
    assert_includes item["body"], "A loop repeats work"
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

  def test_unclear_on_a_concept_page_rewrites_it_and_restores_a_broken_page
    page = File.join(@root, "vault", "Concepts", "stdin-loop.md")
    ENV["FAKE_MODE"] = "rewrite"
    _, done = sse("/api/concepts/stdin-loop/unclear", { "section" => "How it works", "note" => "what reads?" })
    assert_equal({ "exit" => 0, "restored" => false }, done)
    assert_includes File.read(page), "A loop waits for and reads"
    assert_equal File.join(@root, "vault", "Concepts"), fake["cwd"]
    assert_equal File.read(File.join(Byox::PLUGIN_DIR, "skills/byox-teach/SKILL.md")), fake["argv"][fake["argv"].index("--append-system-prompt") + 1]

    before = File.read(page)
    ENV["FAKE_MODE"] = "break"
    out, done = sse("/api/concepts/stdin-loop/unclear", { "section" => "Gotchas", "note" => "?" })
    assert_includes out, "so the page was restored"
    assert_equal [true, before], [done["restored"], File.read(page)]
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
