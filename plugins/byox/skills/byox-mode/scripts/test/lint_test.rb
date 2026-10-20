# frozen_string_literal: true

require_relative "helper"

# One seeded defect per lint rule. Each test asserts the rule fires on the right
# lesson or step, and the clean fixture proves no rule fires without a defect.
class LintTest < Minitest::Test
  def setup
    @root = Fixture.build
  end

  def teardown = FileUtils.rm_rf(@root)

  def lint(lesson: nil, offline: true)
    Byox::Checks.lint(Fixture.course(@root), Fixture.config(@root), lesson:, offline:).map { [_1.check, _1.where, _1.message] }
  end

  def assert_finding(check, where, findings = lint)
    hit = findings.find { _1[0] == check && _1[1] == where }
    assert hit, "expected #{check} at #{where}, got #{findings.inspect}"
    hit
  end

  def test_clean_fixture_has_no_findings
    assert_empty lint
  end

  def test_sections_present
    Fixture.edit_lesson(@root, "01-ping") { _1.sub(/## Task\n.*?(?=## Tests)/m, "") }
    assert_finding(:sections_present, "01-ping")
  end

  def test_three_hints
    Fixture.edit_lesson(@root, "02-store") { _1.sub(/^ +- Removing from a Hash returns the old value.\n/, "") }
    _, _, msg = assert_finding(:three_hints, "02-store")
    assert_includes msg, "step 02.2: has 2 hints"
  end

  def test_front_matter
    Fixture.edit_lesson(@root, "02-store") { _1.sub("verify: sh course/verify/02.2.sh", 'verify: ""') }
    _, _, msg = assert_finding(:front_matter, "02-store")
    assert_includes msg, "verify is empty"
  end

  def test_hint3_contains_no_solution_line
    Fixture.edit_lesson(@root, "02-store") do
      _1.sub('"Use `fetch` with `\"(nil)\"` as the default for GET."', %q('Type: when "GET" then puts store.fetch(args[0], "(nil)")'))
    end
    _, _, msg = assert_finding(:hint3_no_solution, "02.1")
    assert_includes msg, 'store.fetch(args[0], "(nil)")'
  end

  def test_prose_contains_no_solution_line
    Fixture.edit_lesson(@root, "01-ping") { _1.sub("## Task\n", "## Task\n\n    $stdin.each_line do |line|\n") }
    _, _, msg = assert_finding(:no_solution_leak, "01.1")
    assert_includes msg, "$stdin.each_line do |line|"
  end

  def test_links_resolve_offline_rejects_malformed_urls
    Fixture.edit_lesson(@root, "01-ping") { _1.sub("https://ruby-doc.org/3.4/IO.html", "ruby-doc.org/IO") }
    assert_finding(:links_resolve, "01-ping")
  end

  def test_links_resolve_online_reports_dead_links
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    Thread.new do
      loop do
        s = server.accept
        line = s.gets
        s.gets until s.gets == "\r\n" rescue nil
        code = line.include?("/dead") ? "404 Not Found" : "200 OK"
        s.write("HTTP/1.1 #{code}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        s.close
      end
    rescue IOError
      nil
    end
    Fixture.edit_lesson(@root, "01-ping") do
      _1.sub("https://redis.io/docs/latest/develop/reference/protocol-spec/", "http://127.0.0.1:#{port}/alive")
        .sub("https://ruby-doc.org/3.4/IO.html", "http://127.0.0.1:#{port}/dead")
    end
    findings = lint(lesson: "01-ping", offline: false)
    _, _, msg = assert_finding(:links_resolve, "01-ping", findings)
    assert_includes msg, "/dead: HTTP 404"
    assert_equal 1, findings.size
  ensure
    server&.close
  end

  def test_resources_need_two_and_none_blocklisted
    File.write(File.join(@root, "vault", "resource-blocklist.md"), "- https://redis.io/docs/latest/commands/set/ | 2026-10-20 | mini-redis/02-store\n")
    _, _, msg = assert_finding(:resources, "02-store")
    assert_includes msg, "is on the blocklist"
  end

  def test_outline_matches_files
    Fixture.edit_lesson(@root, "02-store") { _1.sub("title: DEL removes a key", "title: DEL deletes") }
    assert_finding(:outline_matches_files, "02-store")
    FileUtils.cp(File.join(@root, "mini-redis/course/lessons/02-store.md"), File.join(@root, "mini-redis/course/lessons/03-extra.md"))
    assert_finding(:outline_matches_files, "03-extra")
  end

  def test_tests_exist
    FileUtils.rm_rf(File.join(@root, "mini-redis/course/tests/02.1"))
    assert_finding(:tests_exist, "02.1")
  end

  def test_random_values_in_tests
    File.write(File.join(@root, "mini-redis/course/tests/02.2/del_test.rb"), <<~RUBY)
      require "minitest/autorun"
      class DelTest < Minitest::Test
        def test_fixed
          assert_equal "1", `printf 'SET a 1\\nDEL a\\n' | ruby main.rb`.lines.last.strip
        end
      end
    RUBY
    assert_finding(:random_values_in_tests, "02.2")
  end

  def test_concept_pages
    FileUtils.rm(File.join(@root, "vault", "Concepts", "key-value-store.md"))
    _, _, msg = assert_finding(:concept_pages, "02-store")
    assert_includes msg, "key-value-store is missing"
  end

  def test_cli_lint_flags_stubs_and_exits_nonzero
    Fixture.edit_lesson(@root, "02-store") { _1.sub("## Task\n", "## Task\n\nTODO(byox)\n") }
    out, status = Open3.capture2e(File.expand_path("../byox", __dir__), "lint", File.join(@root, "mini-redis"), "--offline")
    assert_equal 1, status.exitstatus
    assert_equal "sections_present\t02-store\tlesson is still a stub\n", out
  end
end
