# frozen_string_literal: true

module Byox
  PLUGIN_DIR = File.expand_path("../../../../..", __dir__)
  WEB_DIR = File.expand_path("../../web", __dir__)
  DEFAULT_ROOT = "/run/media/mohamed/storage/MO/Projects/BuildYourOwnX"
  DEFAULT_VAULT = "/home/mohamed/ObsidianVault/1- resource/buildYourOwnXLessons"
  DEFAULT_AGENT_CMD = "claude -p"

  # byox.yml at the courses root. Read only, never written by byox.
  Config = Data.define(:root, :vault, :agent_cmd) do
    def self.load(root = nil)
      root = File.expand_path(root || ENV["BYOX_ROOT"] || DEFAULT_ROOT)
      path = File.join(root, "byox.yml")
      raw = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      new(root:, vault: File.expand_path(raw["vault"] || DEFAULT_VAULT, root), agent_cmd: (raw["agent_cmd"] || DEFAULT_AGENT_CMD).to_s)
    end

    # A course dir sits directly under the root, so its parent holds byox.yml when one exists.
    def self.for_course(course_dir)
      parent = File.dirname(File.expand_path(course_dir))
      File.exist?(File.join(parent, "byox.yml")) ? load(parent) : load
    end

    def concepts_dir = File.join(vault, "Concepts")
    def courses_note_dir = File.join(vault, "Courses")
    def blocklist_path = File.join(vault, "resource-blocklist.md")
    def concept_path(slug) = File.join(concepts_dir, "#{slug}.md")

    def blocklist
      return [] unless File.exist?(blocklist_path)

      File.readlines(blocklist_path).filter_map { |l| l[/\A- (\S+)/, 1] }
    end

    def course_dirs = Dir[File.join(root, "*", "course", "course.md")].sort.map { File.dirname(_1, 2) }
  end
end
