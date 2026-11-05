# frozen_string_literal: true

require_relative "helper"

# A compiled course releases only lessons a lesson-reviewer read. The reviewer leaves
# course/reviews/<lesson>.md; a lesson without one stays building.
class ReviewTest < Minitest::Test
  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown = FileUtils.rm_rf(@root)

  def findings = Byox::Checks.lint(Byox::Course.load(@project), Fixture.config(@root), offline: true).select { _1.check == :review }.map(&:message)

  def test_every_reviewed_lesson_passes
    assert_empty findings
  end

  def test_a_released_lesson_without_a_review_is_named
    FileUtils.rm(File.join(@project, "course/reviews/02-store.md"))
    msgs = findings
    assert(msgs.any? { _1.include?("02-store") && _1.include?("lesson-reviewer") }, msgs.inspect)
  end

  def test_a_building_lesson_needs_no_review
    FileUtils.rm(File.join(@project, "course/reviews/02-store.md"))
    path = File.join(@project, "course/course.md")
    File.write(path, File.read(path).sub("  - id: 02-store\n", "  - id: 02-store\n    building: true\n"))
    assert_empty findings
  end

  def test_an_approved_course_is_not_held_to_it
    FileUtils.rm_rf(File.join(@project, "course/reviews"))
    path = File.join(@project, "course/course.md")
    File.write(path, File.read(path).sub("status: compiled", "status: approved"))
    assert_empty findings
  end

  def test_the_reviewer_agent_is_told_to_write_the_file
    agent = File.read(File.expand_path("../../../../agents/lesson-reviewer.md", __dir__))
    assert_includes agent, "course/reviews/<lesson-id>.md"
  end
end
