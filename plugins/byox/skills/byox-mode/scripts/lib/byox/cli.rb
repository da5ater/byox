# frozen_string_literal: true

require "optparse"

module Byox
  module Cli
    USAGE = <<~TXT
      usage:
        byox site     [--root DIR] [--port 4917]
        byox lint     COURSE_DIR [--lesson ID] [--offline]
        byox strength COURSE_DIR [--lesson ID] [--step ID]
        byox new      COURSE_DIR
        byox split    TRANSCRIPT OUT_DIR
        byox match    LECTURES_DIR REPO [--until REF]
        byox tag      COURSE_DIR STEP_ID [--from REPO SHA] [--force]
        byox sync     [--root DIR]
        byox shot URL OUT.png [--size 1280x800] [--wait MS]
        byox visual-diff TARGET.png ACTUAL.png [--tolerance 0.02] [--coarse 8] [--out DIFF.png]
        byox feedback add TEXT [--page HASH] | list [--open] | mark ID... --pr URL   [--root DIR]
      Exit codes: 0 ok, 1 check failed, 2 bad input.
    TXT

    STUB = "TODO(byox)"

    module_function

    def run(argv)
      cmd = argv.shift
      return usage unless %w[site lint strength new split match tag sync feedback shot visual-diff].include?(cmd)

      opts = {}
      args = OptionParser.new do |o|
        o.on("--root DIR") { opts[:root] = _1 }
        o.on("--port N", Integer) { opts[:port] = _1 }
        o.on("--lesson ID") { opts[:lesson] = _1 }
        o.on("--step ID") { opts[:step] = _1 }
        o.on("--offline") { opts[:offline] = true }
        o.on("--until REF") { opts[:until] = _1 }
        o.on("--from REPO") { opts[:from] = _1 }
        o.on("--force") { opts[:force] = true }
        o.on("--page HASH") { opts[:page] = _1 }
        o.on("--size WxH") { opts[:size] = _1 }
        o.on("--wait MS", Integer) { opts[:wait] = _1 }
        o.on("--tolerance F", Float) { opts[:tolerance] = _1 }
        o.on("--coarse N", Integer) { opts[:coarse] = _1 }
        o.on("--out FILE") { opts[:out] = _1 }
        o.on("--open") { opts[:open] = true }
        o.on("--pr URL") { opts[:pr] = _1 }
      end.parse(argv)
      send("cmd_#{cmd.tr("-", "_")}", args, opts)
    rescue OptionParser::ParseError, ArgumentError, FormatError => e
      warn e.message
      2
    end

    def usage
      warn USAGE
      2
    end

    def cmd_site(_args, opts)
      config = Config.load(opts[:root])
      running = Site.start(config, port: opts[:port] || 4917)
      puts "byox: #{config.course_dirs.size} course(s) at http://127.0.0.1:#{running.port}"
      $stdout.flush
      %w[INT TERM].each { |sig| trap(sig) { Thread.new { running.stop } } }
      running.thread.join
      0
    end

    def cmd_lint(args, opts)
      dir = args.fetch(0) { return usage }
      course = Course.load(dir)
      findings = Checks.lint(course, Config.for_course(dir), lesson: opts[:lesson], offline: opts[:offline])
      findings += stubs(course, opts[:lesson])
      findings.each { puts _1 }
      findings.empty? ? 0 : 1
    end

    def stubs(course, lesson)
      (lesson ? [lesson] : course.outline.map(&:id)).filter_map do |id|
        path = course.lesson_path(id)
        Finding.new(:sections_present, id, "lesson is still a stub") if File.exist?(path) && File.read(path).include?(STUB)
      end
    end

    def cmd_strength(args, opts)
      dir = args.fetch(0) { return usage }
      rows = Checks.strength(Course.load(dir), lesson: opts[:lesson], step: opts[:step])
      puts %w[step prev_exit this_exit verdict].join("\t")
      rows.each { puts _1 }
      rows.all? { %w[ok exempt].include?(_1.verdict) } ? 0 : 1
    end

    # Idempotent: writes only what is missing, so it is safe to rerun after writers start.
    def cmd_new(args, _opts)
      dir = args.fetch(0) { return usage }
      course = Course.load(dir)
      cdir = course.course_dir
      write_missing(File.join(cdir, ".gitignore"), "solution/\nstate.json\n.cache/\n")
      course.outline.each do |l|
        write_missing(course.lesson_path(l.id), lesson_stub(l))
        l.steps.each do |s|
          FileUtils.mkdir_p(File.join(cdir, "tests", s.id))
          write_missing(File.join(cdir, "verify", "#{s.id}.sh"), "#!/bin/sh\necho '#{STUB}: verify for #{s.id}'\nexit 1\n")
        end
      end
      Solution.init(course)
      puts "scaffolded #{course.outline.size} lessons in #{cdir}"
      0
    end

    def write_missing(path, text)
      return if File.exist?(path)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end

    def lesson_stub(l)
      meta = {
        "byox" => 1, "id" => l.id, "title" => l.title, "track" => l.track, "goal" => STUB,
        "concepts" => [], "resources" => [],
        "steps" => l.steps.map do |s|
          { "id" => s.id, "title" => s.title, "kind" => "backend", "verify" => "sh course/verify/#{s.id}.sh",
            "generators" => [], "generated" => [], "instructions" => STUB, "gotchas" => "", "hints" => [STUB] * 3 }
        end,
      }
      "#{meta.to_yaml}---\n\n## Short read\n\n#{STUB}\n\n## Task\n\n#{STUB}\n\n## Tests in plain English\n\n#{STUB}\n"
    end

    def cmd_split(args, _opts)
      transcript, out = args
      return usage unless transcript && out

      Source.split(transcript, out).each { puts [_1.no, _1.empty ? "empty" : "text", _1.title].join("\t") }
      0
    end

    def cmd_match(args, opts)
      lectures, repo = args
      return usage unless lectures && repo

      puts %w[lecture title sha subject score].join("\t")
      Source.match(lectures, repo, until_ref: opts[:until] || "HEAD").each { puts _1.join("\t") }
      0
    end

    def cmd_tag(args, opts)
      dir, step = args
      return usage unless dir && step

      course = Course.load(dir)
      raise ArgumentError, "#{step} is not in course.md" unless course.step_ids.include?(step)

      from = opts[:from] && [opts[:from], args.fetch(2) { raise ArgumentError, "--from needs REPO SHA" }]
      Solution.tag(course, step, from:, force: opts[:force])
      puts "tagged step-#{step}"
      0
    end

    def cmd_sync(_args, opts)
      config = Config.load(opts[:root])
      config.course_dirs.each do |dir|
        course = Course.load(dir)
        puts CourseNote.write(config, course, State.load(course.state_path))
      end
      0
    end

    def cmd_feedback(args, opts)
      config = Config.load(opts[:root])
      case args.shift
      when "add"
        item = Feedback.add(config, text: args.join(" "), page: opts[:page])
        puts item.id
      when "list"
        items = opts[:open] ? Feedback.open(config) : Feedback.all(config)
        puts %w[id status page text pr].join("\t")
        items.each { |i| puts [i.id, i.status, i.page, i.text.tr("\t\n", "  "), i.pr].join("\t") }
      when "mark"
        raise ArgumentError, "mark needs ids and --pr URL" if args.empty? || opts[:pr].to_s.empty?

        Feedback.mark(config, args, pr: opts[:pr])
      else
        return usage
      end
      0
    end

    def cmd_shot(args, opts)
      url, out = args
      raise ArgumentError, "usage: byox shot URL OUT.png [--size 1280x800] [--wait MS]" unless url && out

      width, height = (opts[:size] || "1280x800").split("x").map(&:to_i)
      Visual.shot(url, out, width:, height:, wait_ms: opts[:wait] || 3000)
      0
    end

    def cmd_visual_diff(args, opts)
      target, actual = args
      raise ArgumentError, "usage: byox visual-diff TARGET.png ACTUAL.png [--tolerance 0.02] [--out DIFF.png]" unless target && actual

      [target, actual].each { raise ArgumentError, "no such file: #{_1}" unless File.file?(_1) }
      limit = opts[:tolerance] || 0.02
      result = Visual.diff(target, actual, out: opts[:out], block: opts[:coarse] || 1)
      unit = result.block > 1 ? "blocks" : "pixels"
      note = result.block > 1 ? ", compared in #{result.block}px blocks" : ""
      puts format("%.2f%% of %s differ (limit %.2f%%), %dx%d%s", result.ratio * 100, unit, limit * 100, result.width, result.height, note)
      result.ratio <= limit ? 0 : 1
    rescue Visual::SizeMismatch => e
      puts e.message
      1
    end
  end
end
