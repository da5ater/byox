# frozen_string_literal: true

require_relative "helper"

# Before any lesson is written, the compile wizard settles the stack and the architecture
# and records them under stack.choices in course.md. A UI step also needs a design to
# replicate, unless the course opted out of designs.
class StackTest < Minitest::Test
  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown = FileUtils.rm_rf(@root)

  def course = Byox::Course.load(@project)
  def findings(check) = Byox::Checks.lint(course, Fixture.config(@root), offline: true).select { _1.check == check }.map(&:message)

  def edit(path)
    full = File.join(@project, path)
    File.write(full, yield(File.read(full)))
  end

  def strip_choices = edit("course/course.md") { _1.sub(/^  choices:\n(    .*\n)+/, "") }

  def set_choices(yaml)
    strip_choices
    edit("course/course.md") { _1.sub(/^stack:\n/, "stack:\n  choices:\n#{yaml.lines.map { |l| "    #{l}" }.join}") }
  end

  def make_ui(step_title_line = '- {id: "01.1"')
    edit("course/lessons/01-ping.md") { _1.sub("kind: cli", "kind: ui") }
  end

  GOOD = "language: ruby\narchitecture: one program\ndesign: none\n"

  def test_a_compiled_course_without_stack_choices_is_flagged
    strip_choices
    msgs = findings(:stack)
    assert(msgs.any? { _1.include?("stack.choices") }, msgs.inspect)
  end

  def test_the_wizard_answers_pass
    assert_empty findings(:stack)
  end

  def test_a_missing_key_and_an_unknown_design_are_named
    set_choices("language: ruby\ndesign: figma\n")
    msgs = findings(:stack)
    assert(msgs.any? { _1.include?("architecture") }, msgs.inspect)
    assert(msgs.any? { _1.include?("design") && _1.include?("figma") }, msgs.inspect)
  end

  def test_a_draft_course_is_not_held_to_it
    strip_choices
    edit("course/course.md") { _1.sub("status: compiled", "status: draft") }
    assert_empty findings(:stack)
  end

  def test_a_ui_step_without_a_design_is_flagged_when_designs_are_on
    set_choices("language: ruby\narchitecture: one program\ndesign: penpot\n")
    make_ui
    msgs = findings(:design_canvas)
    assert(msgs.any? { _1.include?("01.1") }, msgs.inspect)
  end

  def test_a_design_link_or_an_exemption_clears_it
    set_choices("language: ruby\narchitecture: one program\ndesign: penpot\n")
    make_ui
    edit("course/lessons/01-ping.md") { _1.sub("kind: ui", "kind: ui\n    design_url: https://design.penpot.app/#/view?x=1") }
    refute(findings(:design_canvas).any? { _1.include?("01.1") })
    edit("course/lessons/01-ping.md") { _1.sub(/\n\s*design_url:[^\n]*/, "\n    design_exempt: only creates the project") }
    refute(findings(:design_canvas).any? { _1.include?("01.1") })
  end

  def test_no_designs_means_no_design_findings
    set_choices(GOOD)
    make_ui
    assert_empty findings(:design_canvas)
  end
end
