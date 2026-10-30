# frozen_string_literal: true

require_relative "helper"

# A step that takes more than ten numbered instructions is two steps. The learner reads it
# as a wall, so lint says where to split.
class StepSizeTest < Minitest::Test
  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown = FileUtils.rm_rf(@root)

  def findings = Byox::Checks.lint(Byox::Course.load(@project), Fixture.config(@root), offline: true).select { _1.check == :step_size }

  def pad_step_one(count)
    path = File.join(@project, "course/lessons/01-ping.md")
    extra = (5..count).map { "      #{_1}. Extra instruction number #{_1}.\n" }.join
    File.write(path, File.read(path).sub("      4. When the command is PING, print PONG on its own line.\n", "      4. When the command is PING, print PONG on its own line.\n#{extra}"))
  end

  def test_a_short_step_passes
    assert_empty findings
  end

  def test_ten_items_pass_and_eleven_are_flagged_with_the_count
    pad_step_one(10)
    assert_empty findings
    File.write(File.join(@project, "course/lessons/01-ping.md"), File.read(File.join(@project, "course/lessons/01-ping.md")).sub("      10. Extra instruction number 10.\n", "      10. Extra instruction number 10.\n      11. One more.\n"))
    msgs = findings.map(&:message)
    assert(msgs.any? { _1.include?("01.1") && _1.include?("11") && _1.include?("split") }, msgs.inspect)
  end
end
