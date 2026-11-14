# frozen_string_literal: true

require_relative "helper"

# Tests that replace the global fetch pass for one HTTP client only. When the course records
# another client, lint flags them.
class ClientTest < Minitest::Test
  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown = FileUtils.rm_rf(@root)

  def course = Byox::Course.load(@project)
  def findings = Byox::Checks.lint(course, Fixture.config(@root), offline: true).select { _1.check == :client_agnostic_tests }.map(&:message)

  def edit(path)
    full = File.join(@project, path)
    File.write(full, yield(File.read(full)))
  end

  def set_client(client)
    edit("course/course.md") { _1.sub("    design: none\n", "    design: none\n    http_client: #{client}\n") }
  end

  def write_test(body, name: "home.test.jsx")
    FileUtils.mkdir_p(File.join(@project, "course/tests/01.1"))
    File.write(File.join(@project, "course/tests/01.1", name), body)
  end

  def test_a_fetch_stub_is_flagged_when_the_client_is_axios
    set_client("axios")
    write_test("vi.stubGlobal('fetch', vi.fn())\n")
    assert_equal 1, findings.size
    assert_includes findings.first, "axios"
  end

  def test_each_way_of_replacing_fetch_is_caught
    set_client("axios")
    ["global.fetch = jest.fn()", "globalThis.fetch = x", "window.fetch = x", "jest.spyOn(global, 'fetch')", "window.XMLHttpRequest = Fake"].each do |line|
      write_test("#{line}\n")
      assert_equal 1, findings.size, line
    end
  end

  def test_a_fetch_client_may_stub_fetch
    set_client("fetch")
    write_test("vi.stubGlobal('fetch', vi.fn())\n")
    assert_empty findings
  end

  def test_a_network_level_fake_passes
    set_client("axios")
    write_test("import { setupServer } from 'msw/node'\nconst server = setupServer()\n")
    assert_empty findings
  end

  def test_a_course_that_names_no_client_is_not_flagged
    write_test("vi.stubGlobal('fetch', vi.fn())\n")
    assert_empty findings
  end

  def test_only_javascript_tests_are_read
    set_client("axios")
    write_test("global.fetch = nothing\n", name: "notes.txt")
    assert_empty findings
  end
end
