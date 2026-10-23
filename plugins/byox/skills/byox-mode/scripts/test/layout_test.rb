# frozen_string_literal: true

require_relative "helper"

# A project is a folder with two folders: course/ for the agent's work and work/ for the
# learner's own code, so the learner can search their project without course files in it.
class LayoutTest < Minitest::Test
  include SiteHelpers

  def setup
    @root = Dir.mktmpdir("byox-split-")
    fake = File.join(@root, "fake_agent.rb")
    File.write(fake, Fixture::FAKE_AGENT)
    MiniRedis.build(@root, agent_cmd: "ruby #{fake}", layout: :split)
    @project = File.join(@root, "mini-redis")
    @work = File.join(@project, "work")
    @log = File.join(@root, "fake.json")
    ENV["FAKE_LOG"] = @log
    @site = Byox::Site.start(Fixture.config(@root), port: 0)
  end

  def teardown
    ENV.delete("FAKE_LOG")
    stop_site
  end

  def api(path) = "/api/courses/mini-redis#{path}"
  def write_work(step) = File.write(File.join(@work, "main.rb"), Fixture.solution_code(step))

  def test_a_project_is_two_folders_and_the_course_knows_where_the_learner_works
    course = Byox::Course.load(@project)
    assert_equal ["split", @work], [course.layout, course.app_dir]
    assert_equal %w[course work], Dir.children(@project).sort
    refute_includes Dir.children(@work), "course", "nothing of the course is inside the learner's folder"
  end

  def test_an_inline_course_still_keeps_the_app_in_the_project_folder
    inline = Fixture.build
    course = Byox::Course.load(File.join(inline, "mini-redis"))
    assert_equal ["inline", File.join(inline, "mini-redis")], [course.layout, course.app_dir]
  ensure
    FileUtils.rm_rf(inline) if inline
  end

  def test_verify_runs_in_the_work_folder_and_finds_the_course_through_byox_course
    write_work("01.1")
    out, done = sse(api("/steps/01.1/verify"))
    assert done["ok"], out
    assert_equal "green", done["step_status"]
    refute File.exist?(File.join(@work, "course")), "verify must not need a course folder inside work/"
  end

  def test_verify_is_red_when_the_learners_code_is_missing
    _, done = sse(api("/steps/01.1/verify"))
    refute done["ok"]
  end

  def test_strength_checks_every_step_without_a_course_link_in_the_app
    rows = Byox::Checks.strength(Byox::Course.load(@project))
    assert_equal %w[ok ok ok ok], rows.map(&:verdict), rows.map(&:to_s).inspect
  end

  def test_compare_reads_the_learners_files_from_work
    File.write(File.join(@work, "main.rb"), "puts 'mine'\n")
    assert_equal 200, json(:post, api("/lessons/01-ping/skip"))[0]
    code, body = json(:get, api("/lessons/01-ping/compare"))
    assert_equal 200, code
    patch = body["files"].find { _1["path"] == "main.rb" }["patch"]
    assert_includes patch, "yours/main.rb"
    assert_includes patch, "+puts 'mine'".sub("+", "-"), "the learner's line is on the 'yours' side of the diff"
  end

  def test_the_coach_sees_a_diff_of_the_work_folder
    File.write(File.join(@work, "main.rb"), "puts 'PING'\n")
    course = Byox::Course.load(@project)
    input = Byox::JobInput.new(course:, config: Fixture.config(@root), lesson: course.lesson("01-ping"), step: nil, section: nil,
                               note: nil, failure_path: nil, target: nil)
    Dir.mktmpdir do |tmp|
      built = Byox::AgentJobs.build_context(input, tmp)
      assert_includes File.read(File.join(built, "learner.diff")), "+puts 'PING'"
    end
  end

  def test_new_scaffolds_work_with_its_own_git_repo_and_nothing_else
    dir = File.join(@root, "fresh")
    FileUtils.mkdir_p(File.join(dir, "course"))
    File.write(File.join(dir, "course", "course.md"), <<~MD)
      ---
      byox: 1
      layout: split
      title: Fresh
      status: approved
      lessons:
        - id: 10-start
          title: Start
          steps:
            - {id: "10.1", title: First}
      ---
    MD
    out, status = Open3.capture2e(File.expand_path("../byox", __dir__), "new", dir)
    assert status.success?, out
    assert_equal [".git"], Dir.children(File.join(dir, "work")).sort, "work/ starts empty apart from its own git repo"
    assert system("git", "-C", File.join(dir, "work"), "rev-parse", "-q", "--verify", "HEAD", out: File::NULL), "work/ has a first commit, so diffs work"
    stub = File.read(File.join(dir, "course/lessons/10-start.md"))
    assert_includes stub, %(verify: sh "$BYOX_COURSE/verify/10.1.sh")
    assert File.file?(File.join(dir, "course/verify/10.1.sh"))
    assert_equal %w[course work], Dir.children(dir).sort
  end

  def test_lint_resolves_byox_course_paths_in_verify_commands
    File.delete(File.join(@project, "course/verify/01.1.sh"))
    findings = Byox::Checks.lint(Byox::Course.load(@project), Fixture.config(@root), lesson: "01-ping", offline: true)
    assert(findings.any? { _1.check == :tests_exist && _1.message.include?("verify/01.1.sh") }, findings.inspect)
  end
end

class InlineLayoutTest < Minitest::Test
  include SiteHelpers

  def setup = start_site
  def teardown = stop_site

  def test_verify_scripts_get_byox_course_in_every_layout
    File.write(File.join(@app_dir, "course/verify/01.1.sh"), "#!/bin/sh\necho \"$BYOX_COURSE\"\nexit 1\n")
    out, = sse("/api/courses/mini-redis/steps/01.1/verify")
    assert_equal "#{@app_dir}/course\n", out
  end
end
