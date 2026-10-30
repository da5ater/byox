# frozen_string_literal: true

require_relative "helper"

# Plain, short writing is checkable. A Short read is a brief, and one instruction is one action.
class WritingSizeTest < Minitest::Test
  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown = FileUtils.rm_rf(@root)

  def findings(check) = Byox::Checks.lint(Byox::Course.load(@project), Fixture.config(@root), offline: true).select { _1.check == check }.map(&:message)

  def words(n) = Array.new(n) { "word#{_1}" }.join(" ")

  def test_a_short_read_within_the_limit_passes
    assert_empty findings(:short_read_size)
  end

  def test_a_long_short_read_is_flagged_with_its_length
    Fixture.edit_lesson(@root, "01-ping") { _1.sub("## Short read\n", "## Short read\n\n#{words(230)}\n") }
    msgs = findings(:short_read_size)
    assert(msgs.any? { _1.include?("01-ping") && _1.match?(/has \d+ words/) && _1.include?("limit is 200") }, msgs.inspect)
  end

  def test_code_blocks_do_not_count_toward_the_short_read
    block = "```\n#{words(300)}\n```"
    Fixture.edit_lesson(@root, "01-ping") { _1.sub("## Short read\n", "## Short read\n\n#{block}\n") }
    assert_empty findings(:short_read_size)
  end

  def test_one_long_instruction_is_flagged_by_its_number
    Fixture.edit_lesson(@root, "01-ping") { _1.sub("      2. Read stdin one line at a time until it closes.\n", "      2. Read stdin one line at a time until it closes and #{words(60)}.\n") }
    msgs = findings(:item_size)
    assert(msgs.any? { _1.include?("01.1") && _1.include?("item 2") }, msgs.inspect)
  end

  def test_short_instructions_pass
    assert_empty findings(:item_size)
  end
end
