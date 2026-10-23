# frozen_string_literal: true

require_relative "helper"

class EvidenceTest < Minitest::Test
  def setup
    @root = Fixture.build
    @home = Dir.mktmpdir("byox-home-")
  end

  def teardown
    FileUtils.rm_rf([@root, @home])
  end

  def byox(*args)
    out, status = Open3.capture2e({ "HOME" => @home }, File.expand_path("../byox", __dir__), *args, "--root", @root)
    [status.exitstatus, out]
  end

  def store = Byox::Store.new(Fixture.course(@root))

  def test_redact_hides_keys_and_tokens_but_keeps_the_sentence
    text = "Called https://x.app/mcp?userToken=eyJhbGciOiJBMjU2S1ciLCJlbmMi.abc and used gho_16C7e42F292c6912E7710c838347Ae178B4a, Bearer abc.def.ghi, password=hunter2 ok"
    out = Byox::Evidence.redact(text)
    refute_match(/eyJhbGci|gho_16C7|abc\.def\.ghi|hunter2/, out)
    assert_includes out, "userToken=REDACTED"
    assert_includes out, "password=REDACTED"
    assert_includes out, "ok"
  end

  def test_evidence_lists_what_the_learner_struggled_with_per_course
    5.times { store.apply({ "type" => "verify", "step" => "01.1", "exit" => 1 }) }
    store.apply({ "type" => "hint", "step" => "01.1", "n" => 3 })
    store.apply({ "type" => "verify", "step" => "01.1", "exit" => 0 })
    store.apply({ "type" => "feedback", "kind" => "unclear", "lesson" => "01-ping", "section" => "short_read",
                  "note" => "what is a server? I used userToken=SECRETKEY123 in the example" })
    code, out = byox("evidence")
    assert_equal 0, code, out
    assert_includes out, "# byox evidence"
    assert_includes out, "## Mini Redis (mini-redis)"
    assert_includes out, "Stack: "
    assert_includes out, "Used all 3 hints on 01.1."
    assert_includes out, "6 verify attempts on 01.1."
    assert_includes out, "01.1: passed after 6 attempts"
    assert_includes out, "what is a server?"
    refute_includes out, "SECRETKEY123", "secrets in learner notes never reach the digest"
    assert_includes out, "userToken=REDACTED"
  end

  def test_evidence_notes_a_step_that_was_tried_and_never_passed
    3.times { store.apply({ "type" => "verify", "step" => "01.1", "exit" => 1 }) }
    _, out = byox("evidence")
    assert_includes out, "01.1: 3 attempts, not passed"
  end

  def test_evidence_includes_open_feedback_and_course_health
    assert_equal 0, byox("feedback", "add", "The hint button is easy to miss", "--page", "#/c/mini-redis/01-ping")[0]
    _, out = byox("evidence")
    assert_includes out, "## Open feedback"
    assert_includes out, "The hint button is easy to miss (#/c/mini-redis/01-ping)"
    assert_match(/Lint \(offline\): (clean|\d+ findings?)/, out)
  end

  def test_since_filters_feedback_by_date
    store.apply({ "type" => "feedback", "kind" => "broken", "lesson" => "01-ping", "note" => "old report", "at" => "2020-01-01T00:00:00Z" })
    store.apply({ "type" => "feedback", "kind" => "broken", "lesson" => "01-ping", "note" => "new report" })
    _, out = byox("evidence", "--since", "2026-01-01")
    assert_includes out, "new report"
    refute_includes out, "old report"
  end

  def encoded(path) = path.gsub(/[^A-Za-z0-9]/, "-")

  def write_transcript(dir, name, prompt)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, name), [
      { type: "summary", note: "session metadata" },
      { type: "user", message: { role: "user", content: prompt } },
      { type: "assistant", message: { role: "assistant", content: "ok" } }
    ].map { JSON.generate(_1) }.join("\n") + "\n")
  end

  def test_transcripts_lists_only_this_projects_sessions_that_used_byox
    dir = File.join(@home, ".claude/projects", encoded(@root))
    write_transcript(dir, "a.jsonl", "/byox-mode this transcript ~/Downloads/x.txt, Rails 8")
    write_transcript(dir, "b.jsonl", "fix the login bug in the billing service")
    other = File.join(@home, ".claude/projects", "-some-other-project")
    write_transcript(other, "c.jsonl", "/byox-mode private chat from another project")

    code, out = byox("transcripts")
    assert_equal 0, code, out
    rows = out.lines.drop(1).map { _1.chomp.split("\t") }
    assert_equal 1, rows.size, out
    assert_equal File.join(dir, "a.jsonl"), rows[0][0]
    assert_includes rows[0].last, "/byox-mode this transcript"
    refute_includes out, "private chat"
  end

  def test_transcripts_is_quiet_when_there_are_none
    code, out = byox("transcripts")
    assert_equal [0, "path\tbytes\tmodified\tfirst prompt\n"], [code, out]
  end
end
