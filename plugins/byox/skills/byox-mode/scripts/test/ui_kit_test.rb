# frozen_string_literal: true

require_relative "helper"

# If the course picked a UI kit, the first step that draws a component installs it. A
# plain version built first and swapped later teaches the wrong thing.
class UiKitTest < Minitest::Test
  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown = FileUtils.rm_rf(@root)

  def edit(path)
    full = File.join(@project, path)
    File.write(full, yield(File.read(full)))
  end

  def findings = Byox::Checks.lint(Byox::Course.load(@project), Fixture.config(@root), offline: true).select { _1.check == :ui_kit }.map(&:message)

  def choose_kit(kit)
    edit("course/course.md") { _1.sub("    design: none\n", "    design: none\n    ui_kit: #{kit}\n") }
  end

  def make_first_step_ui(generators)
    edit("course/lessons/01-ping.md") { _1.sub("    kind: cli\n    verify: sh course/verify/01.1.sh\n    generators: []\n", "    kind: ui\n    design_exempt: no design here\n    verify: sh course/verify/01.1.sh\n    generators: #{generators}\n") }
  end

  def test_no_ui_kit_chosen_means_no_findings
    make_first_step_ui("[]")
    assert_empty findings
  end

  def test_a_ui_kit_with_a_first_ui_step_that_does_not_install_it_is_flagged
    choose_kit("shadcn/ui, radix")
    make_first_step_ui("[]")
    msgs = findings
    assert(msgs.any? { _1.include?("01.1") && _1.include?("shadcn") }, msgs.inspect)
  end

  def test_a_first_ui_step_that_runs_the_kits_generator_passes
    choose_kit("shadcn/ui, radix")
    make_first_step_ui("[\"npx shadcn@latest init\"]")
    assert_empty findings
  end

  def test_a_course_with_no_ui_steps_is_not_asked_for_a_kit
    choose_kit("shadcn/ui, radix")
    assert_empty findings
  end
end
