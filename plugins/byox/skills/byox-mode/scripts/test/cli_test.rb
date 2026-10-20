# frozen_string_literal: true

require_relative "helper"

class CliTest < Minitest::Test
  BYOX = File.expand_path("../byox", __dir__)

  def setup = @dir = Dir.mktmpdir("byox-cli-")
  def teardown = FileUtils.rm_rf(@dir)

  def byox(*args, env: {})
    out, st = Open3.capture2e(env, BYOX, *args)
    [st.exitstatus, out]
  end

  def git(dir, *args) = Open3.capture2("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", *args).first

  def upstream
    repo = File.join(@dir, "upstream")
    FileUtils.mkdir_p(repo)
    git(repo, "init", "-q")
    [["app.rb", "puts 1\n", "gem devise for authentication (log in, log out)"],
     ["notes.txt", "x\n", "Misc"],
     ["app.rb", "puts 2\n", "gem pundit - authorization for courses"]].each do |file, text, msg|
      File.write(File.join(repo, file), text)
      git(repo, "add", "-A")
      git(repo, "commit", "-q", "-m", msg)
    end
    repo
  end

  def test_split_drops_section_headers_and_marks_empty_lectures
    t = File.join(@dir, "t.txt")
    File.write(t, "=== Intro ===\n\n--- Gem Devise for authentication ---\nSo we add devise.\n=== Scrambled ===\n--- Useful links ---\n[No transcript available]\n--- TEXT: add a table ---\n\n[No transcript available for this lecture]\n")
    code, out = byox("split", t, File.join(@dir, "lectures"))
    assert_equal [0, "001\ttext\tGem Devise for authentication\n002\tempty\tUseful links\n003\tempty\tTEXT: add a table\n"], [code, out]
    assert_equal "Gem Devise for authentication\n\nSo we add devise.\n", File.read(File.join(@dir, "lectures", "001-gem-devise-for-authentication.txt"))
  end

  def test_match_pairs_lectures_with_commits_in_order
    repo = upstream
    lectures = File.join(@dir, "lectures")
    FileUtils.mkdir_p(lectures)
    { "001-a.txt" => "Gem Devise for authentication", "002-b.txt" => "Cloud9 disk space", "003-c.txt" => "Gem Pundit: authorization for courses" }
      .each { |f, title| File.write(File.join(lectures, f), "#{title}\n\ntext\n") }
    code, out = byox("match", lectures, repo)
    rows = out.lines.drop(1).map { _1.chomp.split("\t", -1) }
    assert_equal 0, code
    assert_equal ["gem devise for authentication (log in, log out)", "", "gem pundit - authorization for courses"], rows.map { _1[3] }
  end

  def test_match_aligns_corsego_titles_without_a_wrong_jump_derailing_later_rows
    repo = File.join(@dir, "corsego")
    FileUtils.mkdir_p(repo)
    git(repo, "init", "-q")
    ["first commit", "controller home index", "gem haml-rails", "gem bootstrap-rubygem", "scaffold Courses",
     "install action_text", "gem faker", "gem devise", "add_users_to_courses relationship", "add_fields_to_courses",
     "gem ransack for search in navbar"].each_with_index do |msg, i|
      File.write(File.join(repo, "f.txt"), "#{i}\n")
      git(repo, "add", "-A")
      git(repo, "commit", "-q", "-m", msg)
    end
    lectures = File.join(@dir, "corsego-lectures")
    FileUtils.mkdir_p(lectures)
    ["hello world - generate a static page", "gem haml-rails - more RoR-friendly way of editing HTML",
     "add a Courses table", "TEXT: add a Courses table", "action_text - rich text editor",
     "gem devise for authentication (log in, log out)", "course belong_to user - relationships"].each_with_index do |title, i|
      body = title.start_with?("TEXT:") ? "[No transcript available for this lecture]" : "words"
      File.write(File.join(lectures, format("%03d-x.txt", i + 1)), "#{title}\n\n#{body}\n")
    end
    _, out = byox("match", lectures, repo)
    got = out.lines.drop(1).to_h { r = _1.chomp.split("\t", -1); [r[1], r[3]] }
    assert_equal "gem haml-rails", got["gem haml-rails - more RoR-friendly way of editing HTML"]
    assert_equal "scaffold Courses", got["add a Courses table"]
    assert_equal "", got["TEXT: add a Courses table"], "empty lectures carry no code"
    assert_equal "install action_text", got["action_text - rich text editor"]
    assert_equal "gem devise", got["gem devise for authentication (log in, log out)"]
    assert_equal "add_users_to_courses relationship", got["course belong_to user - relationships"]
  end

  def test_new_scaffolds_stubs_once_and_never_overwrites
    app = File.join(@dir, "corsego")
    FileUtils.mkdir_p(File.join(app, "course"))
    File.write(File.join(app, "course", "course.md"), <<~MD)
      ---
      title: Corsego
      status: approved
      lessons:
        - id: 01-new-app
          title: A new app
          steps:
            - {id: "01.1", title: Generate the app}
      ---
    MD
    assert_equal 0, byox("new", app)[0]
    lesson = File.join(app, "course", "lessons", "01-new-app.md")
    assert_equal "Generate the app", Byox::Course.load(app).lesson("01-new-app").steps[0].title
    assert_equal "base\n", git(File.join(app, "course", "solution"), "tag")
    assert File.directory?(File.join(app, "course", "tests", "01.1"))

    File.write(lesson, File.read(lesson).sub("## Task", "## Task\n\nWritten by a writer."))
    assert_equal 0, byox("new", app)[0]
    assert_includes File.read(lesson), "Written by a writer."
    code, out = byox("lint", app, "--offline")
    assert_equal 1, code
    assert_includes out, "sections_present\t01-new-app\tlesson is still a stub"
  end

  def test_tag_from_upstream_commit
    root = Fixture.build
    repo = upstream
    sha = git(repo, "rev-list", "--max-count=1", "HEAD~2").strip
    app = File.join(root, "mini-redis")
    code, out = byox("tag", app, "01.1", "--from", repo, sha, "--force")
    assert_equal [0, "tagged step-01.1\n"], [code, out]
    assert_equal "puts 1\n", git(File.join(app, "course", "solution"), "show", "step-01.1:app.rb")
    assert_equal 2, byox("tag", app, "09.9")[0]
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_tag_marks_shebang_files_executable_even_when_the_repo_ignores_file_modes
    root = Fixture.build
    app = File.join(root, "mini-redis")
    sol = File.join(app, "course", "solution")
    git(sol, "config", "core.filemode", "false")
    FileUtils.mkdir_p(File.join(sol, "bin"))
    File.write(File.join(sol, "bin", "rails"), "#!/usr/bin/env ruby\nputs 1\n")
    File.chmod(0o644, File.join(sol, "bin", "rails"))
    File.write(File.join(sol, "notes.txt"), "plain\n")
    assert_equal 0, byox("tag", app, "01.1", "--force")[0]
    modes = git(sol, "ls-tree", "-r", "step-01.1").lines.to_h { m, _, _, path = _1.split(/\s+/, 4); [path.strip, m] }
    assert_equal "100755", modes["bin/rails"], "a shebang file must stay executable in exports"
    assert_equal "100644", modes["notes.txt"]
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_sync_regenerates_course_notes_from_state
    root = Fixture.build
    File.write(File.join(root, "mini-redis", "course", "state.json"),
               JSON.generate({ "steps" => { "01.1" => { "passed_at" => "t", "attempts" => 1 } } }))
    code, out = byox("sync", "--root", root)
    assert_equal [0, "#{root}/vault/Courses/mini-redis.md\n"], [code, out]
    assert_includes File.read(out.strip), "Progress: 1 of 4 steps. Current: 01-ping Talk over stdin."
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_unknown_command_prints_usage
    code, out = byox("nope")
    assert_equal 2, code
    assert_includes out, "byox strength COURSE_DIR"
  end
end
