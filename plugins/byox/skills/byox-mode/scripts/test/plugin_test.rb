# frozen_string_literal: true

require_relative "helper"

# Promises the skills make in prose, checked as structure.
class PluginTest < Minitest::Test
  PLUGIN = File.expand_path("../../../..", __dir__)

  def manifest = JSON.parse(File.read(File.join(PLUGIN, ".claude-plugin/plugin.json")))

  def front_matter(path) = YAML.safe_load(File.read(path)[/\A---\n(.*?)\n---/m, 1])

  def test_every_agent_in_the_manifest_exists_and_is_named_after_its_file
    manifest["agents"].each do |rel|
      path = File.join(PLUGIN, rel)
      assert File.file?(path), "#{rel} is listed but missing"
      assert_equal File.basename(rel, ".md"), front_matter(path)["name"], "#{rel} must carry its own name"
    end
  end

  def test_reviewers_and_the_coach_cannot_write
    %w[optimize-reviewer optimize-synthesizer coach].each do |name|
      tools = front_matter(File.join(PLUGIN, "agents/#{name}.md"))["tools"].to_s.split(/,\s*/)
      assert_empty tools & %w[Write Edit NotebookEdit], "#{name} must stay read only, it has #{tools.inspect}"
    end
  end

  def test_the_optimize_skill_names_only_agents_and_files_that_exist
    skill = File.read(File.join(PLUGIN, "skills/byox-optimize/SKILL.md"))
    agents = skill.scan(/`byox:([\w-]+)`/).flatten.uniq
    refute_empty agents
    agents.each { |a| assert_includes manifest["agents"], "./agents/#{a}.md", "#{a} is not a registered agent" }
    skill.scan(/`(references\/[\w.-]+)`/).flatten.each do |ref|
      assert File.file?(File.join(PLUGIN, "skills/byox-optimize", ref)), "#{ref} is missing"
    end
    assert_includes skill, "The agent budget is these three and no more."
  end

  def test_the_lenses_the_skill_hands_out_are_defined
    lenses = File.read(File.join(PLUGIN, "skills/byox-optimize/references/lenses.md"))
    %w[friction pipeline].each { |l| assert_match(/^## #{l}$/, lenses) }
  end

  def test_every_byox_command_the_skills_mention_exists
    usage = Open3.capture2e(File.expand_path("../byox", __dir__)).first
    text = Dir[File.join(PLUGIN, "skills/**/*.md"), File.join(PLUGIN, "agents/*.md")].map { File.read(_1) }.join("\n")
    text.scan(/\bB (evidence|transcripts|feedback|shot|visual-diff|lint|strength|new|tag|sync|site|split|match|migrate)\b/).flatten.uniq.each do |cmd|
      assert_includes usage, "byox #{cmd}", "a skill uses `B #{cmd}`, which the CLI does not offer"
    end
  end

  # Gotchas were dropped: they did not help the learner. Old courses keep theirs, so the
  # parser still reads the field, but no instruction may ask an agent to write one.
  def test_no_instruction_asks_for_gotchas
    files = Dir[File.join(PLUGIN, "skills/**/*.md"), File.join(PLUGIN, "agents/*.md")]
    hits = files.flat_map do |f|
      File.readlines(f).each_with_index.filter_map { |l, i| "#{f.delete_prefix("#{PLUGIN}/")}:#{i + 1}: #{l.strip[0, 90]}" if l.match?(/gotcha/i) }
    end
    allowed = hits.select { _1.match?(/\A(skills\/byox-mode\/references\/course-format\.md|agents\/lesson-writer\.md):\d+: .*(do not write|never write)/i) }
    assert_equal %w[agents/lesson-writer.md skills/byox-mode/references/course-format.md], allowed.map { _1[/\A[^:]+/] }.sort,
                 "only the format doc and the writer may say, once each, that gotchas are not written"
    assert_empty hits - allowed, "these instructions still mention gotchas:\n#{(hits - allowed).join("\n")}"
  end

  def test_the_writer_is_told_not_to_write_gotchas
    writer = File.read(File.join(PLUGIN, "agents/lesson-writer.md"))
    assert_match(/Never write gotchas/, writer)
  end
end
