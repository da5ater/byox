# frozen_string_literal: true

require_relative "helper"

class StateTest < Minitest::Test
  S = Byox::State
  ST = Byox::Status

  def setup
    @root = Fixture.build
    @course = Fixture.course(@root)
    @outline = @course.outline
  end

  def teardown = FileUtils.rm_rf(@root)

  def apply(state, *events) = events.reduce(state) { |s, e| S.reduce(s, { "at" => "t#{s['steps'].size}" }.merge(e)) }
  def pass(state, *steps) = apply(state, *steps.map { { "type" => "verify", "step" => _1, "exit" => 0 } })

  def test_verify_counts_attempts_and_green_is_sticky
    s = apply(S.empty, { "type" => "verify", "step" => "01.1", "exit" => 1 },
              { "type" => "verify", "step" => "01.1", "exit" => 0, "at" => "first-green" },
              { "type" => "verify", "step" => "01.1", "exit" => 1 })
    assert_equal({ "attempts" => 3, "last_exit" => 1, "passed_at" => "first-green" }, s["steps"]["01.1"])
    assert_equal :green, ST.step(@outline, s, "01.1")
  end

  def test_reduce_does_not_mutate_its_input
    s = S.empty
    pass(s, "01.1")
    assert_equal({}, s["steps"])
  end

  def test_hints_never_go_down
    s = apply(S.empty, { "type" => "hint", "step" => "01.1", "n" => 2 }, { "type" => "hint", "step" => "01.1", "n" => 1 })
    assert_equal 2, ST.hints_revealed(s, "01.1")
  end

  def test_lessons_and_steps_unlock_in_order
    s = S.empty
    assert_equal [:open, :locked], @outline.map { ST.lesson(@outline, s, _1.id) }
    assert_equal [:open, :locked, :locked, :locked], @course.step_ids.map { ST.step(@outline, s, _1) }
    s = pass(s, "01.1")
    assert_equal [:green, :open], %w[01.1 01.2].map { ST.step(@outline, s, _1) }
    refute ST.solution_unlocked?(@outline, s, "01-ping")
    s = pass(s, "01.2")
    assert_equal [:green, :open], @outline.map { ST.lesson(@outline, s, _1.id) }
    assert ST.solution_unlocked?(@outline, s, "01-ping")
    assert_equal "02-store", ST.current_lesson(@outline, s).id
    assert_equal({ "done" => 2, "total" => 4 }, ST.progress(@outline, s))
  end

  def test_skip_unlocks_the_next_lesson_and_the_solution
    s = apply(S.empty, { "type" => "skip", "lesson" => "01-ping" })
    assert_equal [:skipped, :open], @outline.map { ST.lesson(@outline, s, _1.id) }
    assert ST.solution_unlocked?(@outline, s, "01-ping")
    assert_includes ST.weaknesses(@outline, s), "Skipped 01-ping Talk over stdin."
  end

  def test_weakness_log_comes_from_facts
    s = apply(S.empty, *(1..3).map { { "type" => "hint", "step" => "01.1", "n" => _1 } },
              *Array.new(5) { { "type" => "verify", "step" => "01.1", "exit" => 1 } },
              { "type" => "feedback", "kind" => "unclear", "lesson" => "01-ping", "section" => "task", "note" => "what is stdin?" })
    assert_equal ["Used all 3 hints on 01.1.", "5 verify attempts on 01.1.",
                  "Marked task of Talk over stdin unclear: \"what is stdin?\""], ST.weaknesses(@outline, s)
  end

  def test_store_writes_atomically_and_projects_the_course_note
    config = Fixture.config(@root)
    store = Byox::Store.new(@course, on_change: ->(st) { Byox::CourseNote.write(config, @course, st) })
    threads = Array.new(8) { Thread.new { store.apply({ "type" => "verify", "step" => "01.1", "exit" => 1 }) } }
    threads.each(&:join)
    assert_equal 8, JSON.parse(File.read(@course.state_path))["steps"]["01.1"]["attempts"]
    assert_empty Dir[File.join(@course.course_dir, "*.tmp")]
    note = File.read(File.join(@root, "vault", "Courses", "mini-redis.md"))
    assert_includes note, "| 01-ping Talk over stdin | open | 0/2 | 0 | 8 |"
    assert_includes note, "8 verify attempts on 01.1."
  end
end
