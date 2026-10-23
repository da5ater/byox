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

  # The deep dive is pstack's teach, which runs how and why. They are copied in so the
  # plugin does not depend on pstack, with only the pstack wiring taken out.
  DEEP_DIVE = %w[byox-teach byox-how byox-why].freeze

  def test_the_deep_dive_skills_are_internal_copies_with_their_license
    DEEP_DIVE.each do |name|
      dir = File.join(PLUGIN, "skills", name)
      meta = front_matter(File.join(dir, "SKILL.md"))
      assert_equal name, meta["name"]
      assert_equal false, meta["user-invocable"], "#{name} is used internally, not typed"
      assert File.file?(File.join(dir, "LICENSE-pstack")), "#{name} must carry pstack's MIT license"
      assert_includes File.read(File.join(dir, "SKILL.md")), "Copied from the", "#{name} says where it came from"
    end
  end

  def test_teach_runs_how_and_why_and_they_are_present_with_their_references
    teach = File.read(File.join(PLUGIN, "skills/byox-teach/SKILL.md"))
    assert_includes teach, "`byox-how`"
    assert_includes teach, "`byox-why`"
    %w[how/references/explainer-prompt.md how/references/explorer-prompt.md why/references/epistemics.md why/references/investigator-prompt.md
       why/references/synthesizer-prompt.md why/references/source-playbook.md why/references/sources/code-archaeology.md].each do |rel|
      name, rest = rel.split("/", 2)
      assert File.file?(File.join(PLUGIN, "skills/byox-#{name}", rest)), "byox-#{name} is missing #{rest}"
    end
  end

  def test_no_pstack_wiring_is_left_in_the_copies
    DEEP_DIVE.flat_map { Dir[File.join(PLUGIN, "skills", _1, "**/*.md")] }.each do |f|
      text = File.read(f)
      %w[pstack-models poteto-mode].each { |w| refute_includes text, w, "#{f.delete_prefix(PLUGIN)} still names #{w}" }
      refute_match(/platform mapping/i, text, "#{f.delete_prefix(PLUGIN)} still has the Codex or Copilot note")
    end
  end

  def test_every_byox_skill_a_skill_names_exists
    names = Dir[File.join(PLUGIN, "skills/*")].map { File.basename(_1) }
    Dir[File.join(PLUGIN, "skills/**/*.md")].each do |f|
      File.read(f).scan(/`(byox-(?:how|why|teach|optimize|mode))`/).flatten.uniq.each do |n|
        assert_includes names, n, "#{f.delete_prefix(PLUGIN)} names a skill that does not exist: #{n}"
      end
    end
  end

  # byox-teach runs byox-how and byox-why, which spawn agents. A spawned agent cannot spawn
  # agents, so the lead session writes deep dives, between a lesson's writer and reviewer.
  def test_the_lead_writes_deep_dives_and_the_lesson_writer_does_not
    writer = File.read(File.join(PLUGIN, "agents/lesson-writer.md"))
    refute_match(/byox-teach|concept page you own|Concept pages you own/i, writer, "the lesson writer must not be told to write deep dives")
    compile = File.read(File.join(PLUGIN, "skills/byox-mode/playbooks/compile.md"))
    assert_match(/\*\*Deep dives\.\*\*.*byox-teach.*in this session/m, compile)
    assert_operator compile.index("**Deep dives.**"), :<, compile.index("**Review.**"), "deep dives come before the reviewer"
    assert_operator compile.index("**Lint and strength.**"), :<, compile.index("**Deep dives.**")
    add = File.read(File.join(PLUGIN, "skills/byox-mode/playbooks/add-lessons.md"))
    assert_match(/compile\.md\b.* steps 4 to 9/, add, "add-lessons must follow the renumbered compile steps")
    assert_includes File.read(File.join(PLUGIN, "skills/byox-mode/SKILL.md")), "byox-how"
  end
end
