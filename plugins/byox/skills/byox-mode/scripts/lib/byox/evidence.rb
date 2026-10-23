# frozen_string_literal: true

module Byox
  # What byox needs to improve itself, gathered in one place and without judgment: how
  # each course went for the learner, what they flagged, and which of their Claude Code
  # sessions used byox. The byox-optimize skill hands this to reviewers.
  module Evidence
    SECRET = /(?:user_?token|token|api[_-]?key|secret|password)=[^\s&"')]+|eyJ[\w.-]{20,}|gh[pousr]_\w{20,}|sk-[\w-]{20,}|Bearer\s+\S+/i

    module_function

    def redact(text)
      text.to_s.gsub(SECRET) do |m|
        name = m[/\A(?:user_?token|token|api[_-]?key|secret|password)(?==)/i]
        name ? "#{name}=REDACTED" : "REDACTED"
      end
    end

    def digest(config, since: nil)
      out = ["# byox evidence", "", "Generated #{State.now}. Root: #{config.root}.#{since ? " Feedback since #{since}." : ''}", ""]
      courses = config.course_dirs.sort
      out << "No courses under this root yet." if courses.empty?
      courses.each { |dir| out.concat(course_section(config, dir, since)) }
      out.concat(open_feedback(config, since))
      out.join("\n") + "\n"
    end

    def course_section(config, dir, since)
      course = Course.load(dir)
      state = State.load(course.state_path)
      progress = Status.progress(course.outline, state)
      out = ["## #{course.title} (#{course.slug})", "", "Status #{course.status}. #{progress['done']} of #{progress['total']} steps done. #{stack_line(course)}", ""]
      notes = state["feedback"].select { |f| since.nil? || f["at"].to_s >= since }
      out << "Learner friction:"
      weak = Status.weaknesses(course.outline, state.merge("feedback" => notes))
      out.concat(weak.empty? ? ["- none recorded"] : weak.map { "- #{redact(_1)}" })
      out << ""
      out << "Steps:"
      out.concat(step_lines(state))
      out << ""
      out << "Notes the learner left, newest last:"
      out.concat(notes.empty? ? ["- none"] : notes.map { |f| "- #{f['at']} #{f['kind']} #{[f['lesson'], f['step'], f['section']].compact.join('/')}: #{redact(f['note'] || f['url'])}" })
      out << ""
      out << lint_line(course, config)
      audit = File.join(course.course_dir, "audit.md")
      out.concat(["", "Audit (course/audit.md), first lines:", *File.readlines(audit).first(40).map { "> #{redact(_1.chomp)}" }]) if File.file?(audit)
      out << ""
    rescue FormatError => e
      ["## #{File.basename(dir)}", "", "This course does not parse: #{e.message}", ""]
    end

    def stack_line(course)
      stack = course.meta["stack"]
      return "Stack: not recorded." unless stack.is_a?(Hash) && stack["target"]

      "Stack: #{stack['target']}#{stack['ported'] ? " (ported from #{stack['original']})" : ''}."
    end

    def step_lines(state)
      steps = state["steps"].sort.map do |id, f|
        n = f["attempts"].to_i
        if f["passed_at"] then "- #{id}: passed after #{n} attempts" if n > 1
        elsif n.positive? then "- #{id}: #{n} attempts, not passed"
        end
      end.compact
      first_try = state["steps"].count { |_, f| f["passed_at"] && f["attempts"].to_i == 1 }
      passed = state["steps"].count { |_, f| f["passed_at"] }
      steps << "- first-try passes: #{first_try} of #{passed}"
    end

    def lint_line(course, config)
      findings = Checks.lint(course, config, offline: true)
      return "Lint (offline): clean" if findings.empty?

      ["Lint (offline): #{findings.size} finding#{'s' if findings.size != 1}", *findings.first(8).map { "- #{_1}" }].join("\n")
    rescue StandardError => e
      "Lint (offline): could not run, #{e.message}"
    end

    def open_feedback(config, since)
      items = Feedback.open(config).select { |i| since.nil? || i.at.to_s >= since }
      ["## Open feedback", "", *(items.empty? ? ["- none"] : items.map { "- #{redact(_1.text)}#{_1.page.to_s.empty? ? '' : " (#{_1.page})"}" }), ""]
    end

    # Session transcripts of this project that used byox. Only this project's folder under
    # ~/.claude/projects is read. Other projects' chats are private and never touched.
    def transcripts(config)
      dirs = [config.root, config.plugin_repo].compact.map { real(_1) }.uniq.map { File.join(Dir.home, ".claude", "projects", _1.gsub(/[^A-Za-z0-9]/, "-")) }
      files = dirs.flat_map { |d| Dir[File.join(d, "*.jsonl"), File.join(d, "*", "*.jsonl")] }
      files.select { mentions_byox?(_1) }.sort_by { -File.mtime(_1).to_f }.map do |path|
        [path, File.size(path), File.mtime(path).utc.iso8601, first_prompt(path)]
      end
    end

    # Claude Code names a project's folder after its real path, never a symlink to it.
    def real(path) = File.exist?(path) ? File.realpath(path) : File.expand_path(path)

    def mentions_byox?(path) = File.foreach(path).any? { _1.match?(/byox/i) }

    def first_prompt(path)
      File.foreach(path) do |line|
        rec = JSON.parse(line) rescue next
        next unless rec["type"] == "user"

        content = rec.dig("message", "content")
        text = content.is_a?(Array) ? content.filter_map { _1["text"] if _1.is_a?(Hash) }.join(" ") : content.to_s
        text = text.strip.tr("\n\t", "  ")
        next if text.empty? || text.start_with?("<")

        return redact(text)[0, 120]
      end
      ""
    end
  end
end
