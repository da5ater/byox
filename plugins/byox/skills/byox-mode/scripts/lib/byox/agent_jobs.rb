# frozen_string_literal: true

# Every runtime button that needs Claude is one row here, and AgentJobs.run is the
# only caller of the configured agent command (byox.yml `agent_cmd`).
module Byox
  # target is the one file the job may rewrite. It is snapshotted before the run.
  JobInput = Data.define(:course, :config, :lesson, :step, :section, :note, :failure_path, :target)

  AgentJob = Data.define(:kind, :system_file, :allowed, :disallowed, :workdir, :prompt, :after)

  AGENT_JOBS = {
    # The coach runs in a throwaway dir holding only the lesson, the failure, the
    # learner's diff and concept pages. Headless Read still accepts absolute paths,
    # so Read deny rules (which also cover Grep and Glob) wall off the solution and the mentor's source.
    explain: AgentJob.new(
      kind: :explain, system_file: "agents/coach.md", allowed: "Read,Glob,Grep",
      disallowed: lambda { |j|
        walls = %w[solution source].map { "Read(/#{File.join(j.course.course_dir, _1)}/**)" }
        ["Bash,Edit,Write,WebFetch,WebSearch", *walls].join(",")
      },
      workdir: :context,
      prompt: lambda { |j|
        "Step #{j.step.id} (#{j.step.title}) failed its verify. In this directory: lesson.md, " \
          "failure.txt, learner.diff and concepts/. Explain the failure as the coach."
      },
      after: nil
    ),
    # Rewrites one section of one lesson. The lesson is restored if lint fails afterwards.
    unclear: AgentJob.new(
      kind: :unclear, system_file: "agents/lesson-writer.md", allowed: "Read,Edit,Glob,Grep",
      disallowed: "Bash,Write", workdir: :course,
      prompt: lambda { |j|
        "Unclear mode. The learner marked the section '#{j.section}' of #{j.target} as unclear. " \
          "Their note: #{j.note}\nRewrite only that section, in place, following " \
          "#{File.join(PLUGIN_DIR, 'skills/byox-mode/references/course-format.md')}. Change nothing else. " \
          "Never add solution code."
      },
      after: :lint_or_restore
    ),
    # Rewrites one section of a concept page. The page is restored if a heading goes missing.
    unclear_concept: AgentJob.new(
      kind: :unclear_concept, system_file: "skills/byox-teach/SKILL.md", allowed: "Read,Edit,Glob,Grep",
      disallowed: "Bash,Write", workdir: :vault,
      prompt: lambda { |j|
        "Unclear mode. The learner marked the section '#{j.section}' of the concept page #{j.target} as unclear. " \
          "Their note: #{j.note}\nRewrite only that section, in place, with the writing rules of this skill and " \
          "#{File.join(PLUGIN_DIR, 'skills/byox-mode/references/concept-rubric.md')}. Keep every heading."
      },
      after: :concept_or_restore
    ),
    # Adds lessons to a compiled course. The agent follows the add-lessons playbook, which
    # spawns one writer and one reviewer per new lesson, so Agent is allowed here.
    add_lessons: AgentJob.new(
      kind: :add_lessons, system_file: "skills/byox-mode/playbooks/add-lessons.md",
      allowed: "Read,Edit,Write,Glob,Grep,Bash,Agent", disallowed: "", workdir: :course,
      prompt: lambda { |j|
        "/byox-mode add lessons to the course at #{j.course.dir}, following " \
          "#{File.join(PLUGIN_DIR, 'skills/byox-mode/playbooks/add-lessons.md')}.\nThe learner asks: #{j.note}"
      },
      after: nil
    ),
    # The compiler's fix-lesson playbook, headless. byox reruns lint and strength itself afterwards.
    broken: AgentJob.new(
      kind: :broken, system_file: "skills/byox-mode/playbooks/fix-lesson.md",
      allowed: "Read,Edit,Write,Glob,Grep,Bash", disallowed: "", workdir: :course,
      prompt: lambda { |j|
        "/byox-mode fix-lesson #{j.course.dir} #{j.lesson.id}\nLearner note: #{j.note}\n" \
          "Failing output: #{j.failure_path || 'none'}"
      },
      after: :lint_and_strength
    ),
    # Turns the open feedback into one pull request on the plugin's repo, with before and after screenshots.
    feedback: AgentJob.new(
      kind: :feedback, system_file: "agents/feedback.md", allowed: "Read,Edit,Write,Glob,Grep,Bash", disallowed: "",
      workdir: :plugin_repo,
      prompt: lambda { |j|
        repo = j.config.plugin_repo ? "The local byox checkout is #{j.config.plugin_repo}." : "There is no local byox checkout."
        "Ship mode. Process every open item in #{j.config.feedback_path} following " \
          "#{File.join(PLUGIN_DIR, 'skills/byox-mode/playbooks/feedback.md')}. The courses root is #{j.config.root}. " \
          "The upstream repo is #{j.config.upstream}. #{repo}"
      },
      after: nil
    ),
    # Packages the changes the learner already made in their byox checkout as one pull request.
    feedback_upload: AgentJob.new(
      kind: :feedback_upload, system_file: "agents/feedback.md", allowed: "Read,Edit,Write,Glob,Grep,Bash", disallowed: "",
      workdir: :plugin_repo,
      prompt: lambda { |j|
        "Upload mode. Package the changes in #{j.config.plugin_repo} as one pull request following " \
          "#{File.join(PLUGIN_DIR, 'skills/byox-mode/playbooks/feedback-upload.md')}. The courses root is #{j.config.root}. " \
          "The upstream repo is #{j.config.upstream}. Open notes from the learner are in #{j.config.feedback_path}."
      },
      after: nil
    ),
  }.freeze

  module AgentJobs
    module_function

    def command(job, input)
      denied = job.disallowed.respond_to?(:call) ? job.disallowed.call(input) : job.disallowed
      [*Shellwords.split(input.config.agent_cmd), job.prompt.call(input),
       "--append-system-prompt", File.read(File.join(PLUGIN_DIR, job.system_file)),
       "--allowedTools", job.allowed, *(denied.empty? ? [] : ["--disallowedTools", denied])]
    end

    # emit.(event, data) streams to the page. Returns the final result hash.
    def run(kind, input, &emit)
      job = AGENT_JOBS.fetch(kind)
      Dir.mktmpdir("byox-#{kind}-") do |tmp|
        cwd = { context: -> { build_context(input, tmp) }, vault: -> { input.config.concepts_dir },
                course: -> { input.course.dir }, plugin_repo: -> { input.config.plugin_repo || FileUtils.mkdir_p(File.join(input.config.root, ".byox")).first } }.fetch(job.workdir).call
        snapshot = input.target && File.read(input.target)
        env = { "BYOX_JOB" => kind.to_s, "BYOX_TARGET" => input.target, "BYOX_COURSE" => input.course&.dir }.compact
        code = Shell.stream(command(job, input), cwd:, env:, timeout: 900) { emit.call("line", { "text" => _1 }) }
        result = { "exit" => code }
        job.after ? result.merge(send(job.after, input, snapshot, &emit)) : result
      end
    end

    def build_context(input, dir)
      ctx = File.join(dir, "context")
      FileUtils.mkdir_p(File.join(ctx, "concepts"))
      File.write(File.join(ctx, "lesson.md"), revealed_only(input))
      File.write(File.join(ctx, "failure.txt"), input.failure_path && File.exist?(input.failure_path) ? File.read(input.failure_path) : "")
      File.write(File.join(ctx, "learner.diff"), learner_diff(input.course.dir))
      input.lesson.concepts.each do |slug|
        src = input.config.concept_path(slug)
        FileUtils.cp(src, File.join(ctx, "concepts", "#{slug}.md")) if File.exist?(src)
      end
      ctx
    end

    # The coach must not see a hint the learner has not revealed.
    def revealed_only(input)
      meta, body = Format.split_front_matter(input.lesson.path)
      state = State.load(input.course.state_path)
      meta["steps"].each { |s| s["hints"] = Array(s["hints"]).first(Status.hints_revealed(state, s["id"].to_s)) }
      "#{YAML.dump(meta)}---\n#{body}"
    end

    def learner_diff(dir)
      return "" unless system("git", "-C", dir, "rev-parse", "-q", "--verify", "HEAD", out: File::NULL, err: File::NULL)

      outside = [".", ":(exclude)course"]
      diff, = Open3.capture2("git", "-C", dir, "diff", "--no-color", "HEAD", "--", *outside)
      untracked, = Open3.capture2("git", "-C", dir, "ls-files", "--others", "--exclude-standard", "--", *outside)
      added = untracked.lines.map(&:chomp).first(20).map do |f|
        "new file #{f}\n#{File.read(File.join(dir, f)).lines.first(200).map { "+#{_1}" }.join}"
      end
      [diff, *added].join("\n")
    end

    def lint_or_restore(input, snapshot)
      findings = Checks.lint(input.course, input.config, lesson: input.lesson.id, offline: true)
      return { "restored" => false } if findings.empty?

      File.write(input.target, snapshot)
      findings.each { yield "line", { "text" => "lint: #{_1}\n" } }
      yield "line", { "text" => "Lint failed, so the lesson was restored.\n" }
      { "restored" => true, "findings" => findings.map(&:to_s) }
    end

    def concept_or_restore(input, snapshot)
      missing = begin
        Concept.parse(input.target).missing_headings
      rescue FormatError => e
        [e.message]
      end
      return { "restored" => false } if missing.empty?

      File.write(input.target, snapshot)
      yield "line", { "text" => "Missing #{missing.join(', ')}, so the page was restored.\n" }
      { "restored" => true, "findings" => missing }
    end

    def lint_and_strength(input, _snapshot)
      findings = Checks.lint(input.course, input.config, lesson: input.lesson.id, offline: true)
      rows = Checks.strength(input.course, lesson: input.lesson.id)
      (findings + rows).each { yield "line", { "text" => "#{_1}\n" } }
      { "findings" => findings.map(&:to_s), "strength" => rows.map(&:to_s) }
    rescue FormatError => e
      yield "line", { "text" => "#{e.message}\n" }
      { "findings" => [e.message], "strength" => [] }
    end
  end
end
