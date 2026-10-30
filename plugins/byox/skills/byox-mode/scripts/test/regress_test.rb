# frozen_string_literal: true

require_relative "helper"

# A later step can break an earlier step's check, for example when it adds a login every
# page needs. `strength --regress` reruns each released step's verify on the last tag.
class RegressTest < Minitest::Test
  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown = FileUtils.rm_rf(@root)

  def course = Byox::Course.load(@project)

  def test_every_step_still_passes_on_the_last_tag_of_an_untouched_course
    rows = Byox::Checks.regress(course)
    assert_equal %w[ok ok ok ok], rows.map(&:verdict), rows.map(&:to_s).inspect
  end

  def test_a_step_whose_check_fails_on_a_later_tag_is_reported_as_regressed
    File.write(File.join(@project, "course/verify/01.1.sh"), %(#!/bin/sh\ngrep -q DEL main.rb && exit 1\nexec ruby "course/tests/01.1/ping_test.rb"\n))
    rows = Byox::Checks.regress(course)
    assert_equal({ "01.1" => "regressed" }, rows.reject { _1.verdict == "ok" }.to_h { [_1.step, _1.verdict] }, rows.map(&:to_s).inspect)
  end

  def test_with_a_lesson_it_checks_up_to_that_lessons_last_tag_only
    rows = Byox::Checks.regress(course, lesson: "01-ping")
    assert_equal %w[01.1 01.2], rows.map(&:step)
  end

  def test_the_cli_flag_prints_the_rows_and_exits_non_zero_on_a_regression
    File.write(File.join(@project, "course/verify/01.1.sh"), %(#!/bin/sh\ngrep -q DEL main.rb && exit 1\nexec ruby "course/tests/01.1/ping_test.rb"\n))
    out, status = Open3.capture2e(File.expand_path("../byox", __dir__), "strength", @project, "--regress")
    refute status.success?
    assert_match(/01\.1\t.*\tregressed/, out)
  end
end
