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
    text.scan(/\bB (evidence|transcripts|feedback|shot|visual-diff|lint|strength|new|tag|sync|site|split|match)\b/).flatten.uniq.each do |cmd|
      assert_includes usage, "byox #{cmd}", "a skill uses `B #{cmd}`, which the CLI does not offer"
    end
  end
end
