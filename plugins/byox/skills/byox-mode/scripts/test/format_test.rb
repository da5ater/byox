# frozen_string_literal: true

require_relative "helper"

class FormatTest < Minitest::Test
  def setup
    @root = Fixture.build
    @course = Fixture.course(@root)
  end

  def teardown = FileUtils.rm_rf(@root)

  def test_course_outline_and_derived_tags
    assert_equal "mini-redis", @course.slug
    assert_equal %w[01-ping 02-store], @course.outline.map(&:id)
    assert_equal %w[01.1 01.2 02.1 02.2], @course.step_ids
    assert_equal "base", @course.previous_tag("01.1")
    assert_equal "step-01.2", @course.previous_tag("02.1")
  end

  def test_lesson_parses_front_matter_and_sections
    l = @course.lesson("01-ping")
    assert_equal "Talk over stdin", l.title
    assert_includes l.goal, "PING with PONG"
    assert_equal %i[short_read task tests], l.sections.keys
    assert_includes l.sections[:tests], "**01.1.**"
    s = l.steps.first
    assert_equal ["01.1", "cli", "sh course/verify/01.1.sh", "step-01.1"], [s.id, s.kind, s.verify, s.tag]
    assert_equal 3, s.hints.size
    assert_equal 2, l.resources.size
  end

  def test_two_hints_never_become_a_step
    Fixture.edit_lesson(@root, "01-ping") { _1.sub(/      - "Compare the upcased.*\n/, "") }
    err = assert_raises(Byox::FormatError) { @course.lesson("01-ping") }
    assert_equal [:three_hints], err.problems.map(&:first)
  end

  def test_missing_section_and_bad_yaml_are_reported
    Fixture.edit_lesson(@root, "01-ping") { _1.sub("## Task", "## Tasks") }
    err = assert_raises(Byox::FormatError) { @course.lesson("01-ping") }
    assert_includes err.problems.map(&:last), "section 'Task' is missing or empty"

    Fixture.edit_lesson(@root, "02-store") { _1.sub("title: Store keys", "title: [unclosed") }
    err = assert_raises(Byox::FormatError) { @course.lesson("02-store") }
    assert_equal :front_matter, err.problems.first.first
  end

  def test_concept_headings_must_appear_in_order
    path = File.join(@root, "vault", "Concepts", "stdin-loop.md")
    assert_empty Byox::Concept.parse(path).missing_headings
    File.write(path, File.read(path).sub("## The problem", "## Problem"))
    assert_equal ["The problem"], Byox::Concept.parse(path).missing_headings
  end

  def test_a_concept_page_does_not_need_a_gotchas_section
    path = File.join(@root, "vault", "Concepts", "stdin-loop.md")
    File.write(path, File.read(path).sub(/^## Gotchas\n.*?(?=^## )/m, ""))
    refute_includes File.read(path), "## Gotchas"
    assert_empty Byox::Concept.parse(path).missing_headings
  end

  def test_a_step_without_gotchas_is_a_complete_step
    Fixture.edit_lesson(@root, "01-ping") { |t| t.gsub(/^ {4}gotchas: \|\n(?: {6}.*\n)+/, "") }
    refute_includes File.read(File.join(@root, "mini-redis/course/lessons/01-ping.md")), "gotchas:"
    lesson = @course.lesson("01-ping")
    assert_equal ["", ""], lesson.steps.map(&:gotchas)
    findings = Byox::Checks.lint(Fixture.course(@root), Fixture.config(@root), lesson: "01-ping", offline: true)
    assert_empty findings, findings.inspect
  end

  def test_new_stubs_leave_gotchas_out
    cmd = File.join(@root, "mini-redis/course/course.md")
    File.write(cmd, File.read(cmd).sub(/^lessons:\n/, "lessons:\n  - id: 00-extra\n    title: Extra\n    steps:\n      - {id: \"00.1\", title: First}\n"))
    _, status = Open3.capture2e(File.expand_path("../byox", __dir__), "new", File.join(@root, "mini-redis"))
    assert status.success?
    stub = File.read(File.join(@root, "mini-redis/course/lessons/00-extra.md"))
    assert_includes stub, "instructions:"
    refute_includes stub, "gotchas", "a new lesson stub no longer asks for gotchas"
  end

  def test_generated_globs
    assert Byox::Format.generated?("db/migrate/2024_create_users.rb", ["db/migrate/*_create_users.rb"])
    assert Byox::Format.generated?("test/models/user_test.rb", ["test/**"])
    refute Byox::Format.generated?("app/models/user.rb", ["test/**", "db/*.rb"])
  end

  def test_a_whole_tree_glob_covers_nested_files_and_dotfiles
    %w[app/models/application_record.rb .gitignore .kamal/secrets config/routes.rb].each do |path|
      assert Byox::Format.generated?(path, ["**"]), "** must cover #{path}"
      assert Byox::Format.generated?(path, ["**/*"]), "**/* must cover #{path}"
    end
    assert Byox::Format.generated?(".github/workflows/ci.yml", [".github/**"])
  end
end
