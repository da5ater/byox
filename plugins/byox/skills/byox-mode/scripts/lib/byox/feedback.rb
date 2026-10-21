# frozen_string_literal: true

module Byox
  # The learner's feedback on byox itself: UI changes, bugs, ideas. One JSON line per
  # event in <root>/.byox/feedback.jsonl. A later line for the same id wins, so marking
  # an item is an append and the log keeps its history.
  module Feedback
    Item = Data.define(:id, :at, :text, :page, :status, :pr)

    module_function

    def add(config, text:, page: "")
      text = text.to_s.strip
      raise ArgumentError, "feedback text is empty" if text.empty?

      item = Item.new(id: "fb-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(2)}", at: State.now,
                      text:, page: page.to_s, status: "open", pr: nil)
      append(config, item.to_h)
      item
    end

    def mark(config, ids, pr:)
      known = all(config).map(&:id)
      unknown = ids - known
      raise ArgumentError, "unknown feedback id: #{unknown.join(', ')}" unless unknown.empty?

      ids.each { append(config, { id: _1, status: "in_pr", pr: }) }
    end

    def all(config)
      path = config.feedback_path
      return [] unless File.exist?(path)

      merged = {}
      File.foreach(path) do |line|
        row = JSON.parse(line, symbolize_names: true)
        merged[row[:id]] = (merged[row[:id]] || {}).merge(row)
      end
      merged.values.map { |row| Item.new(**Item.members.to_h { |m| [m, row[m]] }) }
    end

    def open(config) = all(config).select { _1.status == "open" }

    # Files the learner changed in their byox checkout and has not shipped: uncommitted
    # work plus commits that are not on origin/main yet. nil when there is no checkout.
    def changes(config)
      repo = config.plugin_repo
      return nil unless repo && File.directory?(File.join(repo, ".git"))

      git = ->(*a) { Open3.capture2("git", "-C", repo, *a, err: File::NULL).first }
      dirty = git.("status", "--porcelain", "--untracked-files=all").lines.map { _1[3..].strip }
      base = git.("rev-parse", "-q", "--verify", "origin/main").strip
      committed = base.empty? ? [] : git.("diff", "--name-only", "#{base}...HEAD").lines.map(&:strip)
      (dirty + committed).uniq.size
    end

    def append(config, row)
      FileUtils.mkdir_p(File.dirname(config.feedback_path))
      File.open(config.feedback_path, "a") do |f|
        f.flock(File::LOCK_EX)
        f.puts(JSON.generate(row))
      end
    end
  end
end
