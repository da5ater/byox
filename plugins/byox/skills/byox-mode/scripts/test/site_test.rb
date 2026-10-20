# frozen_string_literal: true

require_relative "helper"

class SiteTest < Minitest::Test
  include SiteHelpers

  def setup = start_site
  def teardown = stop_site

  def test_static_shell_and_assets
    code, type, body = http(:get, "/")
    assert_equal [200, "text/html; charset=utf-8"], [code, type]
    assert_includes body, "/assets/app.js"
    assert_equal 200, http(:get, "/assets/vendor/marked.min.js")[0]
    assert_equal 404, http(:get, "/assets/..%2F..%2Flib%2Fbyox.rb")[0]
  end

  def test_home_lists_courses_with_progress
    code, body = json(:get, "/api/courses")
    assert_equal 200, code
    assert_equal [{ "slug" => "mini-redis", "title" => "Mini Redis", "progress" => { "done" => 0, "total" => 4 },
                    "current" => { "id" => "01-ping", "title" => "Talk over stdin" } }], body["courses"]
  end

  def test_locked_lesson_is_refused
    code, body = json(:get, api("/lessons/02-store"))
    assert_equal [403, "locked"], [code, body["status"]]
  end

  def test_hints_are_gated_on_the_server
    _, lesson = json(:get, api("/lessons/01-ping"))
    assert_equal [[], 3], lesson["steps"][0].values_at("hints", "hints_total")
    refute_includes JSON.generate(lesson), "A loop over the lines of stdin"

    assert_equal 409, json(:post, api("/steps/01.1/hints/2"))[0]
    code, body = json(:post, api("/steps/01.1/hints/1"))
    assert_equal [200, 1], [code, body["revealed"]]
    assert_equal ["A loop over the lines of stdin ends by itself when the input closes."], body["hints"]
    assert_equal 200, json(:post, api("/steps/01.1/hints/2"))[0]
    assert_equal 400, json(:post, api("/steps/01.1/hints/4"))[0]
    assert_equal 2, json(:get, api("/lessons/01-ping"))[1]["steps"][0]["hints"].size
    assert_equal 409, json(:post, api("/steps/01.2/hints/1"))[0], "hints on a locked step stay hidden"
  end

  def test_verify_streams_output_and_goes_green_on_exit_zero
    out, done = sse(api("/steps/01.1/verify"))
    assert_includes out, "1 failures"
    assert_equal({ "ok" => false, "exit" => 1, "step_status" => "open", "lesson_status" => "open", "lesson_green" => false }, done)

    learner_writes("01.1")
    out, done = sse(api("/steps/01.1/verify"))
    assert_includes out, "0 failures"
    assert_equal [true, "green", false], done.values_at("ok", "step_status", "lesson_green")
    assert_equal 409, sse(api("/steps/02.1/verify"))[0], "steps in a locked lesson cannot run"
  end

  def test_solution_and_compare_unlock_when_the_lesson_goes_green
    assert_equal 403, json(:get, api("/lessons/01-ping/solution"))[0]
    assert_equal 403, json(:get, api("/lessons/01-ping/compare"))[0]

    learner_writes("01.2")
    sse(api("/steps/01.1/verify"))
    _, done = sse(api("/steps/01.2/verify"))
    assert_equal [true, "green"], done.values_at("lesson_green", "lesson_status")

    code, sol = json(:get, api("/lessons/01-ping/solution"))
    assert_equal 200, code
    assert_equal %w[01.1 01.2], sol["steps"].map { _1["id"] }
    assert_includes sol["steps"][1]["files"][0]["patch"], '+  when "ECHO" then puts args.join(" ")'

    File.write(File.join(@app_dir, "main.rb"), "puts 'mine'\n")
    code, cmp = json(:get, api("/lessons/01-ping/compare"))
    assert_equal 200, code
    assert_includes cmp["files"][0]["patch"], "-puts 'mine'"
    assert_includes cmp["files"][0]["patch"], "--- yours/main.rb"

    state = JSON.parse(File.read(File.join(@app_dir, "course", "state.json")))
    assert state.dig("lessons", "01-ping", "solution_unlocked_at")
    assert_equal "open", json(:get, api(""))[1]["lessons"][1]["status"]
  end

  def test_skip_unlocks_the_next_lesson_and_the_solution
    code, body = json(:post, api("/lessons/01-ping/skip"))
    assert_equal [200, "skipped", "02-store"], [code, body["status"], body["next_lesson"]]
    assert_equal 200, json(:get, api("/lessons/01-ping/solution"))[0]
    assert_equal 200, json(:get, api("/lessons/02-store"))[0]
    assert_equal 404, json(:post, api("/lessons/99-none/skip"))[0]
  end

  def test_bad_resource_shows_the_backup_and_writes_the_blocklist
    _, l = json(:get, api("/lessons/01-ping"))
    first = l["resource"]["url"]
    assert_equal 400, json(:post, api("/lessons/01-ping/bad-resource"), { "url" => "https://example.com" })[0]
    code, body = json(:post, api("/lessons/01-ping/bad-resource"), { "url" => first })
    assert_equal [200, "https://ruby-doc.org/3.4/IO.html"], [code, body["resource"]["url"]]
    assert_includes File.read(File.join(@root, "vault", "resource-blocklist.md")), "- #{first} | "
  end

  def test_concept_page_with_where_it_shows_up
    code, c = json(:get, "/api/concepts/stdin-loop")
    assert_equal 200, code
    assert_includes c["body"], "## How it works"
    assert_equal [{ "course" => "mini-redis", "lesson" => "01-ping", "title" => "Talk over stdin" }], c["where"]
    assert_equal 404, json(:get, "/api/concepts/..%2Fsecret")[0]
  end

  def test_every_state_change_regenerates_the_course_note
    json(:post, api("/steps/01.1/hints/1"))
    note = File.read(File.join(@root, "vault", "Courses", "mini-redis.md"))
    assert_includes note, "| 01-ping Talk over stdin | open | 0/2 | 1 | 0 |"
  end

  def test_a_second_site_on_the_same_root_refuses_to_start
    err = assert_raises(RuntimeError) { Byox::Site.start(Fixture.config(@root), port: 0) }
    assert_includes err.message, "another byox site is running"
  end
end
