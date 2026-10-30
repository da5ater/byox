# frozen_string_literal: true

require_relative "helper"

# A step can name up to two things to read before doing it, each at an exact section and
# with the reason it matters for this step. Lint checks them like any other resource.
class ReadFirstTest < Minitest::Test
  include SiteHelpers

  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown
    stop_site
    FileUtils.rm_rf(@root)
  end

  def edit_lesson = Fixture.edit_lesson(@root, "01-ping") { yield _1 }

  def add_read_first(yaml) = edit_lesson { _1.sub("    kind: cli\n    verify: sh course/verify/01.1.sh\n", "    kind: cli\n    verify: sh course/verify/01.1.sh\n#{yaml}") }

  GOOD = <<~Y.lines.map { "    #{_1}" }.join
    read_first:
      - url: https://ruby-doc.org/3.4/IO.html
        section: "Line IO"
        why: Shows the call that reads one line at a time.
  Y

  def lint(check) = Byox::Checks.lint(Byox::Course.load(@project), Fixture.config(@root), offline: true).select { _1.check == check }.map(&:message)

  def test_a_step_exposes_what_to_read_first
    add_read_first(GOOD)
    s = Byox::Course.load(@project).lesson("01-ping").steps.first
    assert_equal ["https://ruby-doc.org/3.4/IO.html", "Line IO"], [s.read_first.first.url, s.read_first.first.section]
    assert_empty Byox::Course.load(@project).lesson("01-ping").steps.last.read_first
  end

  def test_more_than_two_or_an_entry_without_a_section_or_reason_is_rejected
    add_read_first("    read_first:\n" + (1..3).map { "      - {url: https://example.com/#{_1}, section: s, why: w}\n" }.join)
    err = assert_raises(Byox::FormatError) { Byox::Course.load(@project).lesson("01-ping") }
    assert(err.problems.any? { |_, m| m.include?("read_first") && m.include?("at most 2") }, err.problems.inspect)
  end

  def test_an_entry_missing_its_reason_is_rejected
    add_read_first("    read_first:\n      - {url: https://example.com/a, section: Intro}\n")
    err = assert_raises(Byox::FormatError) { Byox::Course.load(@project).lesson("01-ping") }
    assert(err.problems.any? { |_, m| m.include?("read_first") && m.include?("why") }, err.problems.inspect)
  end

  def test_a_blocklisted_link_is_flagged
    add_read_first(GOOD)
    File.write(Fixture.config(@root).blocklist_path, "- https://ruby-doc.org/3.4/IO.html\n")
    assert(lint(:resources).any? { _1.include?("blocklist") && _1.include?("IO.html") }, lint(:resources).inspect)
  end

  def test_the_lesson_page_data_carries_it
    add_read_first(GOOD)
    @site = Byox::Site.start(Fixture.config(@root), port: 0)
    _, body = json(:get, "/api/courses/mini-redis/lessons/01-ping")
    assert_equal [{ "url" => "https://ruby-doc.org/3.4/IO.html", "section" => "Line IO", "why" => "Shows the call that reads one line at a time." }], body["steps"][0]["read_first"]
    assert_equal [], body["steps"][1]["read_first"]
  end
end
