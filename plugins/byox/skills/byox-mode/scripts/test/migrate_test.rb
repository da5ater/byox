# frozen_string_literal: true

require_relative "helper"

# byox migrate turns an inline course (the learner's app is the project folder, with
# course/ inside it) into a split one (course/ and work/), and keeps its tests working.
class MigrateTest < Minitest::Test
  include SiteHelpers

  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
    @site = nil
  end

  def teardown
    @site&.stop
    FileUtils.rm_rf(@root)
  end

  def byox(*args)
    out, status = Open3.capture2e(File.expand_path("../byox", __dir__), *args)
    [status.exitstatus, out]
  end

  def learner_has_written(step)
    File.write(File.join(@project, "main.rb"), Fixture.solution_code(step))
    File.write(File.join(@project, ".env.example"), "A=1\n")
    FileUtils.mkdir_p(File.join(@project, "lib"))
    File.write(File.join(@project, "lib/helper.rb"), "# mine\n")
    system("git", "-C", @project, "add", "-A", out: File::NULL)
    system("git", "-C", @project, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "mine", out: File::NULL)
  end

  def start_site
    @site = Byox::Site.start(Fixture.config(@root), port: 0)
  end

  def test_the_project_ends_as_two_folders_with_everything_of_the_learners_in_work
    learner_has_written("01.2")
    code, out = byox("migrate", @project)
    assert_equal 0, code, out
    assert_equal %w[course work], Dir.children(@project).sort
    assert_equal [".env.example", ".git", "lib", "main.rb"], Dir.children(File.join(@project, "work")).sort
    assert_equal "mine", `git -C #{File.join(@project, 'work')} log -1 --format=%s`.strip, "the learner's git history moved with the files"
    assert_equal Fixture.solution_code("01.2"), File.read(File.join(@project, "work/main.rb"))
  end

  def test_the_course_declares_the_new_layout_and_its_verify_commands_follow
    byox("migrate", @project)
    course = Byox::Course.load(@project)
    assert_equal ["split", File.join(@project, "work")], [course.layout, course.app_dir]
    verifies = course.lessons.flat_map(&:steps).map(&:verify)
    assert verifies.all? { _1.match?(%r{\Ash "\$BYOX_COURSE/verify/[\d.]+\.sh"\z}) }, verifies.inspect
    assert_equal %(exec ruby "$BYOX_COURSE/tests/01.1/ping_test.rb"), File.readlines(File.join(@project, "course/verify/01.1.sh")).last.strip
  end

  def test_every_step_still_goes_green_after_the_move
    learner_has_written("01.2")
    byox("migrate", @project)
    start_site
    %w[01.1 01.2].each do |step|
      _, _, raw = http(:post, "/api/courses/mini-redis/steps/#{step}/verify")
      assert_includes raw, '"ok":true', "step #{step} should pass from work/: #{raw}"
    end
  end

  def test_the_strength_check_and_lint_still_hold
    byox("migrate", @project)
    rows = Byox::Checks.strength(Byox::Course.load(@project))
    assert_equal %w[ok ok ok ok], rows.map(&:verdict), rows.map(&:to_s).inspect
    findings = Byox::Checks.lint(Byox::Course.load(@project), Fixture.config(@root), offline: true)
    assert_empty findings, findings.inspect
  end

  def test_a_path_that_is_already_quoted_is_not_quoted_twice
    File.write(File.join(@project, "course/verify/01.1.sh"), %(#!/bin/sh\nexec ruby "course/tests/01.1/ping_test.rb" ./course/support/x.rb\n))
    byox("migrate", @project)
    line = File.readlines(File.join(@project, "course/verify/01.1.sh")).last.strip
    assert_equal %(exec ruby "$BYOX_COURSE/tests/01.1/ping_test.rb" "$BYOX_COURSE/support/x.rb"), line
  end

  def test_dry_run_changes_nothing_and_lists_the_plan
    learner_has_written("01.1")
    before = Dir.children(@project).sort
    code, out = byox("migrate", @project, "--dry-run")
    assert_equal 0, code, out
    assert_equal before, Dir.children(@project).sort
    assert_includes out, "move main.rb -> work/main.rb"
    assert_includes out, "rewrite course/verify/01.1.sh"
    refute File.exist?(File.join(@project, "work"))
  end

  def test_it_refuses_to_run_twice_or_over_an_existing_work_folder
    assert_equal 0, byox("migrate", @project)[0]
    code, out = byox("migrate", @project)
    assert_equal 2, code
    assert_match(/already split/, out)

    other = File.join(@root, "second")
    FileUtils.mkdir_p(File.join(other, "work"))
    FileUtils.cp_r(File.join(@root, "mini-redis/course"), File.join(other, "course"))
    File.write(File.join(other, "course/course.md"), File.read(File.join(other, "course/course.md")).sub("layout: split\n", ""))
    code, out = byox("migrate", other)
    assert_equal 2, code
    assert_match(/work already exists/, out)
  end

  def test_course_paths_in_test_files_are_reported_never_rewritten
    path = File.join(@project, "course/tests/01.1/ping_test.rb")
    File.write(path, File.read(path) + "\n# reads course/support/data.json\n")
    code, out = byox("migrate", @project)
    assert_equal 0, code
    assert_match(%r{needs a manual look: course/tests/01\.1/ping_test\.rb:\d+}, out)
    assert_includes File.read(path), "course/support/data.json", "test files are left exactly as written"
  end

  def test_the_log_records_every_move_so_it_can_be_undone
    learner_has_written("01.1")
    byox("migrate", @project)
    log = File.read(File.join(@project, "course/.cache/migrate.log"))
    assert_includes log, "main.rb"
    assert_includes log, "verify/01.1.sh"
  end
end
