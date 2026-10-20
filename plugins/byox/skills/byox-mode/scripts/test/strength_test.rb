# frozen_string_literal: true

require_relative "helper"

class StrengthTest < Minitest::Test
  def setup
    @root = Fixture.build
    @course = Fixture.course(@root)
  end

  def teardown = FileUtils.rm_rf(@root)

  def verdicts(**kw) = Byox::Checks.strength(Fixture.course(@root), **kw).to_h { [_1.step, _1.verdict] }

  def test_real_tests_fail_before_and_pass_after_their_step
    assert_equal({ "01.1" => "ok", "01.2" => "ok", "02.1" => "ok", "02.2" => "ok" }, verdicts)
  end

  def test_a_test_that_passes_at_the_previous_tag_is_weak
    File.write(File.join(@course.course_dir, "tests/02.2/del_test.rb"), <<~RUBY)
      require "minitest/autorun"
      require "open3"
      class DelTest < Minitest::Test
        def test_only_checks_set
          out, = Open3.capture2e("ruby", "main.rb", stdin_data: "SET k\#{rand(99)} v\\n")
          assert_equal "OK\\n", out
        end
      end
    RUBY
    assert_equal({ "02.1" => "ok", "02.2" => "weak" }, verdicts(lesson: "02-store"))
  end

  def test_a_test_that_fails_on_its_own_step_is_broken
    File.write(File.join(@course.course_dir, "tests/01.2/echo_test.rb"), <<~RUBY)
      require "minitest/autorun"
      class EchoTest < Minitest::Test
        def test_impossible = assert_equal(rand(9), 10)
      end
    RUBY
    assert_equal({ "01.2" => "broken" }, verdicts(step: "01.2"))
  end

  def test_cloud_steps_are_exempt
    Fixture.edit_lesson(@root, "01-ping") { _1.sub(%r{kind: cli(\s+verify: sh course/verify/01.2.sh)}, 'kind: cloud\1') }
    assert_equal({ "01.1" => "ok", "01.2" => "exempt" }, verdicts(lesson: "01-ping"))
  end

  def test_the_solution_repo_is_never_touched
    git = ->(*a) { Open3.capture2("git", "-C", @course.solution_dir, *a).first }
    before = [git.("rev-parse", "HEAD"), git.("status", "--porcelain"), git.("worktree", "list")]
    verdicts
    assert_equal before, [git.("rev-parse", "HEAD"), git.("status", "--porcelain"), git.("worktree", "list")]
  end

  def test_cli_exits_nonzero_on_a_weak_step
    File.write(File.join(@course.course_dir, "tests/01.2/echo_test.rb"), "require 'minitest/autorun'\nclass T < Minitest::Test\n  def test_x = assert(rand < 2)\nend\n")
    out, status = Open3.capture2e(File.expand_path("../byox", __dir__), "strength", @course.dir, "--lesson", "01-ping")
    assert_equal 1, status.exitstatus
    assert_equal "step\tprev_exit\tthis_exit\tverdict\n01.1\t1\t0\tok\n01.2\t0\t0\tweak\n", out
  end
end
