# frozen_string_literal: true

require_relative "helper"

# A lesson that is still a stub is only acceptable while the course says it is being built.
class StubGateTest < Minitest::Test
  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
    File.write(File.join(@project, "course/lessons/02-store.md"), "---\ngoal: #{Byox::Cli::STUB}\n---\n#{Byox::Cli::STUB}\n")
  end

  def teardown = FileUtils.rm_rf(@root)

  def lint_output
    Open3.capture2e(File.expand_path("../byox", __dir__), "lint", @project, "--offline").first
  end

  def test_a_stub_that_is_not_marked_building_is_reported
    assert_match(/sections_present\t02-store\tlesson is still a stub/, lint_output)
  end

  def test_a_lesson_marked_building_is_left_out_of_the_whole_course_lint
    path = File.join(@project, "course/course.md")
    File.write(path, File.read(path).sub("  - id: 02-store\n", "  - id: 02-store\n    building: true\n"))
    refute_includes lint_output, "02-store"
  end

  def test_compile_marks_a_course_compiled_only_after_whole_course_lint_passes
    compile = File.read(File.expand_path("../../playbooks/compile.md", __dir__))
    assert_match(/Run `B lint C`.*exits 0/m, compile)
    assert_includes compile, "building: true"
  end
end
