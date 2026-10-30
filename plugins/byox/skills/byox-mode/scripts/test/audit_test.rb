# frozen_string_literal: true

require_relative "helper"

# The audit says which lessons it covered, and every row carries a status. A compiled course
# with open rows, or with released lessons outside the audit, is not done.
class AuditTest < Minitest::Test
  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown = FileUtils.rm_rf(@root)

  def write_audit(text) = File.write(File.join(@project, "course/audit.md"), text)

  def findings = Byox::Checks.lint(Byox::Course.load(@project), Fixture.config(@root), offline: true).select { _1.check == :audit }.map(&:message)

  TABLE = <<~MD
    | # | check | where | what is wrong | suggested fix | status |
    |---|---|---|---|---|---|
  MD

  def test_no_audit_file_means_no_audit_findings
    assert_empty findings
  end

  def test_an_audit_that_covers_every_released_lesson_with_every_row_closed_passes
    write_audit("lessons: 01-ping, 02-store\n\n#{TABLE}| 1 | followable | 01.1 | vague | name the file | fixed |\n| 2 | coverage | 02.1 | gap | add a row | wontfix: out of scope |\n")
    assert_empty findings
  end

  def test_an_open_row_is_reported_with_its_place
    write_audit("lessons: 01-ping, 02-store\n\n#{TABLE}| 1 | followable | 01.1 | vague | name the file | open |\n")
    msgs = findings
    assert(msgs.any? { _1.include?("open") && _1.include?("01.1") }, msgs.inspect)
  end

  def test_a_released_lesson_outside_the_audit_scope_is_reported
    write_audit("lessons: 01-ping\n\n#{TABLE}")
    msgs = findings
    assert(msgs.any? { _1.include?("02-store") }, msgs.inspect)
  end

  def test_a_lesson_marked_building_needs_no_audit
    write_audit("lessons: 01-ping\n\n#{TABLE}")
    path = File.join(@project, "course/course.md")
    File.write(path, File.read(path).sub("  - id: 02-store\n", "  - id: 02-store\n    building: true\n"))
    assert_empty findings
  end

  def test_an_audit_with_no_lessons_line_is_reported
    write_audit("#{TABLE}| 1 | x | 01.1 | y | z | fixed |\n")
    assert(findings.any? { _1.include?("lessons:") })
  end

  def test_the_auditor_agent_is_told_to_write_both
    agent = File.read(File.expand_path("../../../../agents/course-auditor.md", __dir__))
    assert_includes agent, "lessons:"
    assert_includes agent, "status"
    assert_includes File.read(File.expand_path("../../playbooks/add-lessons.md", __dir__)), "course-auditor"
  end
end
