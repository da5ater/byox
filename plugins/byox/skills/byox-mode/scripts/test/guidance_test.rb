# frozen_string_literal: true

require_relative "helper"

# What a learner reads and where they look after a step: teaching pages instead of manuals,
# a read_first decision on every step, ring wording instead of "left out", and links to the
# real code that open only once the step is green.
class GuidanceTest < Minitest::Test
  include SiteHelpers

  def setup
    @root = Fixture.build
    @project = File.join(@root, "mini-redis")
  end

  def teardown
    stop_site
    FileUtils.rm_rf(@root)
  end

  def edit_lesson(id = "01-ping") = Fixture.edit_lesson(@root, id) { yield _1 }
  def lint(check) = Byox::Checks.lint(Byox::Course.load(@project), Fixture.config(@root), offline: true).select { _1.check == check }

  REAL = "    real_code:\n      - {url: https://github.com/acme/app/pull/12/files, label: The PR that added PING}\n"

  def test_a_manual_as_reading_is_flagged_and_a_tutorial_is_not
    edit_lesson { _1.sub("read_first: []\n    kind: cli", "read_first:\n      - {url: https://www.postgresql.org/docs/current/explicit-locking.html, section: Locks, why: locks}\n    kind: cli") }
    assert(lint(:reference_docs).any? { _1.message.include?("postgresql.org") })
    edit_lesson { _1.sub("https://www.postgresql.org/docs/current/explicit-locking.html", "https://vladmihalcea.com/a-beginners-guide-to-database-locking-and-the-lost-update-phenomena/") }
    assert_empty lint(:reference_docs)
  end

  def test_a_step_without_a_read_first_decision_is_named
    assert_empty lint(:read_first)
    edit_lesson { _1.sub("    read_first: []\n", "") }
    assert(lint(:read_first).any? { _1.where == "01.1" })
  end

  def test_left_out_wording_asks_for_the_ring
    edit_lesson { _1.sub("## Task\n", "## Task\n\nThe real server also keeps a log. Leave those out.\n") }
    msgs = lint(:deferred_wording).map(&:message)
    assert(msgs.any? { _1.include?("ring") }, msgs.inspect)
    edit_lesson { _1.sub("Leave those out.", "That comes in ring 2.") }
    assert_empty lint(:deferred_wording)
  end

  def test_real_code_links_parse_and_need_https_and_a_label
    edit_lesson { _1.sub("    kind: cli\n", "    kind: cli\n#{REAL}") }
    s = Byox::Course.load(@project).lesson("01-ping").steps.first
    assert_equal ["https://github.com/acme/app/pull/12/files", "The PR that added PING"], [s.real_code.first.url, s.real_code.first.label]
    edit_lesson { _1.sub("https://github.com/acme/app/pull/12/files", "github.com/acme").sub("label: The PR that added PING", "label: ''") }
    err = assert_raises(Byox::FormatError) { Byox::Course.load(@project).lesson("01-ping") }
    assert_match(/real_code/, err.message)
  end

  def test_the_site_shows_real_code_only_after_the_step_is_green
    edit_lesson { _1.sub("    kind: cli\n", "    kind: cli\n#{REAL}") }
    @site = Byox::Site.start(Fixture.config(@root), port: 0)
    _, before = json(:get, "/api/courses/mini-redis/lessons/01-ping")
    assert_empty before["steps"].first["real_code"]
    store = Byox::Store.new(Byox::Course.load(@project))
    store.apply({ "type" => "verify", "step" => "01.1", "exit" => 0 })
    _, after = json(:get, "/api/courses/mini-redis/lessons/01-ping")
    assert_equal "The PR that added PING", after["steps"].first["real_code"].first["label"]
  end
end
