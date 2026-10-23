# frozen_string_literal: true

require_relative "helper"

# A product can have several projects, such as an API and a frontend. A course declares them
# in course.md, each is a folder in work/ with its own git repo, and verify scripts reach
# them through BYOX_PROJECT_<NAME> instead of guessing relative paths.
class ProjectsTest < Minitest::Test
  include SiteHelpers

  def setup
    @root = Dir.mktmpdir("byox-projects-")
    fake = File.join(@root, "fake_agent.rb")
    File.write(fake, Fixture::FAKE_AGENT)
    MiniRedis.build(@root, agent_cmd: "ruby #{fake}", projects: :two)
    @project = File.join(@root, "mini-redis")
    @work = File.join(@project, "work")
    @api = File.join(@work, "api")
    @client = File.join(@work, "client")
    @site = Byox::Site.start(Fixture.config(@root), port: 0)
  end

  def teardown = stop_site

  def course = Byox::Course.load(@project)
  def api(path) = "/api/courses/mini-redis#{path}"

  def learner_does_step_one
    File.write(File.join(@api, "main.rb"), Fixture.solution_code("01.1"))
    File.write(File.join(@client, "readme.txt"), "client\n")
  end

  def test_projects_are_declared_and_mapped_to_folders
    c = course
    assert_equal %w[api client], c.projects.map(&:name)
    assert_equal [@api, @client], c.projects.map { c.project_dir(_1) }
    assert_equal @api, c.app_dir, "verify runs in the first project"
    env = c.project_env
    assert_equal [c.course_dir, @work, @api, @client],
                 env.values_at("BYOX_COURSE", "BYOX_WORK", "BYOX_PROJECT_API", "BYOX_PROJECT_CLIENT")
  end

  def test_the_work_folder_holds_one_folder_per_project_each_with_its_own_repo
    assert_equal %w[api client], Dir.children(@work).sort
    %w[api client].each { assert File.directory?(File.join(@work, _1, ".git")), "#{_1} has its own git repo" }
  end

  def test_new_creates_every_declared_project_folder_with_a_repo_and_a_first_commit
    dir = File.join(@root, "fresh")
    FileUtils.mkdir_p(File.join(dir, "course"))
    File.write(File.join(dir, "course", "course.md"), <<~MD)
      ---
      byox: 1
      layout: split
      title: Fresh
      status: approved
      projects:
        - {name: api, description: The API}
        - {name: web, description: The site}
      lessons:
        - id: 10-start
          title: Start
          steps:
            - {id: "10.1", title: First}
      ---
    MD
    out, status = Open3.capture2e(File.expand_path("../byox", __dir__), "new", dir)
    assert status.success?, out
    assert_equal %w[api web], Dir.children(File.join(dir, "work")).sort
    %w[api web].each do |name|
      assert_equal [".git"], Dir.children(File.join(dir, "work", name)).sort, "#{name} starts empty apart from its repo"
      assert system("git", "-C", File.join(dir, "work", name), "rev-parse", "-q", "--verify", "HEAD", out: File::NULL), "#{name} has a first commit"
    end
  end

  def test_verify_runs_in_the_first_project_and_can_reach_the_others
    learner_does_step_one
    out, done = sse(api("/steps/01.1/verify"))
    assert done["ok"], out

    File.delete(File.join(@client, "readme.txt"))
    out, done = sse(api("/steps/01.1/verify"))
    refute done["ok"]
    assert_includes out, "client/readme.txt must say client"
  end

  def test_the_solution_maps_onto_the_projects_when_strength_exports_it
    rows = Byox::Checks.strength(course)
    assert_equal %w[ok ok ok ok], rows.map(&:verdict), rows.map(&:to_s).inspect
  end

  def test_the_export_gives_each_project_only_its_own_part_of_the_solution
    Dir.mktmpdir do |tmp|
      Byox::Solution.export_work(course, "step-01.1", tmp)
      assert_equal %w[api client], Dir.children(tmp).sort
      assert_equal ["main.rb"], Dir.children(File.join(tmp, "api")), "api is the solution root without the client subfolder"
      assert_equal ["readme.txt"], Dir.children(File.join(tmp, "client")), "client is the solution's client/ folder on its own"
    end
  end

  def test_compare_matches_each_solution_file_to_the_learners_file_in_the_right_project
    File.write(File.join(@api, "main.rb"), "puts 'mine'\n")
    File.write(File.join(@client, "readme.txt"), "mine\n")
    assert_equal 200, json(:post, api("/lessons/01-ping/skip"))[0]
    code, body = json(:get, api("/lessons/01-ping/compare"))
    assert_equal 200, code
    patches = body["files"].to_h { [_1["path"], _1["patch"]] }
    assert_includes patches["client/readme.txt"], "-mine"
    assert_includes patches["main.rb"], "-puts 'mine'"
  end

  def test_the_coach_sees_the_changes_of_every_project_under_its_own_heading
    File.write(File.join(@api, "main.rb"), "puts 'in api'\n")
    File.write(File.join(@client, "readme.txt"), "in client\n")
    c = course
    input = Byox::JobInput.new(course: c, config: Fixture.config(@root), lesson: c.lesson("01-ping"), step: nil, section: nil,
                               note: nil, failure_path: nil, target: nil)
    Dir.mktmpdir do |tmp|
      diff = File.read(File.join(Byox::AgentJobs.build_context(input, tmp), "learner.diff"))
      assert_includes diff, "### project api"
      assert_includes diff, "### project client"
      assert_includes diff, "+puts 'in api'"
      assert_includes diff, "+in client"
    end
  end

  def test_the_site_lists_the_projects_with_their_folders
    _, map = json(:get, api(""))
    assert_equal [{ "name" => "api", "folder" => "work/api", "description" => "The Ruby program" },
                  { "name" => "client", "folder" => "work/client", "description" => "A tiny second project" }], map["projects"]
    _, lesson = json(:get, api("/lessons/01-ping"))
    assert_equal %w[api client], lesson["projects"].map { _1["name"] }
  end

  def edit_course_md
    path = File.join(@project, "course/course.md")
    File.write(path, yield(File.read(path)))
  end

  def lint_findings = Byox::Checks.lint(course, Fixture.config(@root), offline: true)

  def test_lint_rejects_a_bad_project_declaration
    edit_course_md { _1.sub("{name: client, source: client,", "{name: api, path: ../outside, source: client,") }
    messages = lint_findings.select { _1.check == :projects }.map(&:message)
    assert(messages.any? { _1.include?("duplicate project name api") }, messages.inspect)
    assert(messages.any? { _1.include?("must stay inside work/") }, messages.inspect)
  end

  def test_lint_rejects_a_verify_script_that_names_a_project_that_does_not_exist
    File.write(File.join(@project, "course/verify/01.2.sh"), %(#!/bin/sh\ntest -f "$BYOX_PROJECT_WEB/index.html"\nexec ruby "$BYOX_COURSE/tests/01.2/echo_test.rb"\n))
    messages = lint_findings.select { _1.check == :projects }.map(&:message)
    assert(messages.any? { _1.include?("BYOX_PROJECT_WEB") && _1.include?("01.2") }, messages.inspect)
  end

  def test_a_clean_two_project_course_has_no_project_findings
    assert_empty lint_findings.select { _1.check == :projects }
  end
end

# Regrouping an existing single-project course into named projects, for a course that put
# the frontend inside the API app. The solution tree is not rewritten.
class RegroupTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("byox-regroup-")
    fake = File.join(@root, "fake_agent.rb")
    File.write(fake, Fixture::FAKE_AGENT)
    MiniRedis.build(@root, agent_cmd: "ruby #{fake}", layout: :split)
    @project = File.join(@root, "mini-redis")
    @work = File.join(@project, "work")
    FileUtils.mkdir_p(File.join(@work, "client"))
    File.write(File.join(@work, "client/readme.txt"), "client\n")
    File.write(File.join(@work, "main.rb"), Fixture.solution_code("01.1"))
    File.write(File.join(@project, "course/verify/01.1.sh"), <<~SH)
      #!/bin/sh
      set -e
      test "$(cat client/readme.txt)" = client
      (cd client && test -f readme.txt)
      grep -q 'client/' /dev/null || true
      exec ruby "$BYOX_COURSE/tests/01.1/ping_test.rb"
    SH
  end

  def teardown
    @site&.stop
    FileUtils.rm_rf(@root)
  end

  def byox(*args)
    out, status = Open3.capture2e(File.expand_path("../byox", __dir__), *args)
    [status.exitstatus, out]
  end

  def test_the_main_project_gets_the_apps_files_and_the_other_projects_get_their_own_folder
    code, out = byox("migrate", @project, "--projects", "api,client")
    assert_equal 0, code, out
    assert_equal %w[api client], Dir.children(@work).sort
    assert_equal %w[main.rb], Dir.children(File.join(@work, "api")).reject { _1 == ".git" }.sort
    assert_equal ["readme.txt"], Dir.children(File.join(@work, "client"))
    assert File.directory?(File.join(@work, "api/.git")), "the existing repo moved with the API"
    assert_equal %w[api client], Byox::Course.load(@project).projects.map(&:name)
    assert_equal [".", "client"], Byox::Course.load(@project).projects.map(&:source)
  end

  def test_scripts_reach_the_moved_project_through_its_variable_and_still_pass
    byox("migrate", @project, "--projects", "api,client")
    script = File.read(File.join(@project, "course/verify/01.1.sh"))
    assert_includes script, %(test "$(cat $BYOX_PROJECT_CLIENT/readme.txt)" = client)
    assert_includes script, %((cd "$BYOX_PROJECT_CLIENT" && test -f readme.txt))
    assert_includes script, %(grep -q 'client/' /dev/null), "a path in single quotes is left alone"

    @site = Byox::Site.start(Fixture.config(@root), port: 0)
    Net::HTTP.start("127.0.0.1", @site.port, read_timeout: 60) do |h|
      res = h.request(Net::HTTP::Post.new("/api/courses/mini-redis/steps/01.1/verify", "Content-Type" => "application/json"))
      assert_includes res.body, '"ok":true', res.body
    end
  end

  def test_project_paths_followed_by_shell_punctuation_and_comments_are_handled_like_course_paths
    File.write(File.join(@project, "course/verify/01.1.sh"), <<~SH)
      #!/bin/sh
      set -e
      # the client/ folder holds the second project
      if ! grep -q "x" client/readme.txt; then echo no; fi
      if [ ! -f client/readme.txt ]; then exit 1; fi
      (cat client/readme.txt) > /dev/null
      cd client && test -f readme.txt
      cd ..
      exec ruby "$BYOX_COURSE/tests/01.1/ping_test.rb"
    SH
    byox("migrate", @project, "--projects", "api,client")
    lines = File.readlines(File.join(@project, "course/verify/01.1.sh"), chomp: true)
    assert_equal "# the client/ folder holds the second project", lines[2]
    assert_equal %(if ! grep -q "x" "$BYOX_PROJECT_CLIENT/readme.txt"; then echo no; fi), lines[3]
    assert_equal %(if [ ! -f "$BYOX_PROJECT_CLIENT/readme.txt" ]; then exit 1; fi), lines[4]
    assert_equal %[(cat "$BYOX_PROJECT_CLIENT/readme.txt") > /dev/null], lines[5]
    assert_equal %(cd "$BYOX_PROJECT_CLIENT" && test -f readme.txt), lines[6]
    assert_equal "cd ..", lines[7], "a cd that is not into a project is left alone"
    _, status = Open3.capture2e("sh", "-n", File.join(@project, "course/verify/01.1.sh"))
    assert status.success?, "the rewritten script still parses"
  end

  def test_dry_run_changes_nothing
    before = Dir.children(@work).sort
    code, out = byox("migrate", @project, "--projects", "api,client", "--dry-run")
    assert_equal 0, code, out
    assert_equal before, Dir.children(@work).sort
    assert_includes out, "move work/main.rb -> work/api/main.rb"
    assert_includes out, "keep work/client"
  end

  def test_it_refuses_a_course_that_already_declares_projects
    byox("migrate", @project, "--projects", "api,client")
    code, out = byox("migrate", @project, "--projects", "api,client")
    assert_equal 2, code
    assert_match(/already declares projects/, out)
  end
end
