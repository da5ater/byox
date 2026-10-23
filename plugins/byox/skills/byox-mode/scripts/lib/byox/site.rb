# frozen_string_literal: true

# The local site. It serves one static shell from web/ and a JSON API. Course files
# are re-read on every request, because agents edit them while the site runs.
module Byox
  module Site
    ROUTES = [
      ["GET",  "/",                                               :page],
      ["GET",  "/assets/*path",                                   :asset],
      ["GET",  "/api/courses",                                    :courses],
      ["GET",  "/api/courses/:course",                            :course_map],
      ["GET",  "/api/courses/:course/lessons/:lesson",            :lesson],
      ["POST", "/api/courses/:course/steps/:step/verify",         :verify],       # SSE
      ["POST", "/api/courses/:course/steps/:step/hints/:n",       :hint],
      ["POST", "/api/courses/:course/lessons/:lesson/skip",       :skip],
      ["GET",  "/api/courses/:course/lessons/:lesson/solution",   :solution],     # 403 until green or skipped
      ["GET",  "/api/courses/:course/lessons/:lesson/compare",    :compare],      # 403 until green or skipped
      ["POST", "/api/courses/:course/steps/:step/explain",        :explain],      # SSE, agent
      ["POST", "/api/courses/:course/lessons/:lesson/unclear",    :unclear],      # SSE, agent
      ["POST", "/api/courses/:course/lessons/:lesson/broken",     :broken],       # SSE, agent
      ["POST", "/api/courses/:course/lessons/:lesson/bad-resource", :bad_resource],
      ["POST", "/api/courses/:course/add-lessons",                :add_lessons],     # SSE, agent
      ["GET",  "/api/concepts/:slug",                             :concept],
      ["POST", "/api/concepts/:slug/unclear",                     :unclear_concept], # SSE, agent
      ["GET",  "/api/courses/:course/files/*path",                :course_file],
      ["GET",  "/api/feedback",                                   :feedback_list],
      ["POST", "/api/feedback",                                   :feedback_add],
      ["POST", "/api/feedback/ship",                              :feedback_ship],   # SSE, agent
      ["POST", "/api/feedback/upload",                            :feedback_upload], # SSE, agent
    ].map do |verb, pattern, handler|
      rx = pattern.gsub(/\*(\w+)/, '(?<\1>.+)').gsub(/:(\w+)/, '(?<\1>[^/]+)')
      [verb, Regexp.new("\\A#{rx}\\z"), handler]
    end.freeze

    MIME = { ".html" => "text/html; charset=utf-8", ".js" => "text/javascript", ".css" => "text/css" }.freeze

    Running = Data.define(:server, :thread, :lock) do
      def port = server.addr[1]

      def stop
        server.close
        thread.join(2)
        lock.close
      end
    end

    module_function

    # Holds an flock on <root>/.byox/site.lock for its whole life, so a second site on
    # the same root exits instead of becoming a second writer of state.json.
    def start(config, port:)
      FileUtils.mkdir_p(File.join(config.root, ".byox"))
      lock = File.open(File.join(config.root, ".byox", "site.lock"), File::RDWR | File::CREAT)
      raise "another byox site is running on #{config.root}" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

      server = TCPServer.new("127.0.0.1", port)
      app = App.new(config)
      Running.new(server:, thread: Thread.new { Http.serve(server) { app.call(_1) } }, lock:)
    end

    class NotFound < StandardError; end

    class App
      def initialize(config)
        @config = config
        @verify_locks = Hash.new { |h, k| h[k] = Mutex.new }
        @job_locks = Hash.new { |h, k| h[k] = Mutex.new }
        @guard = Mutex.new
      end

      def call(req)
        ROUTES.each do |verb, rx, handler|
          next unless verb == req.method && (m = rx.match(req.path))

          params = m.named_captures.transform_values { URI.decode_www_form_component(_1) }.transform_keys(&:to_sym)
          return send(handler, req, **params)
        end
        Http.json(404, { "error" => "no route" })
      rescue NotFound => e
        Http.json(404, { "error" => e.message })
      rescue FormatError => e
        Http.json(500, { "error" => e.message })
      end

      private

      def page(_req) = Http::Response.new(200, MIME[".html"], File.read(File.join(WEB_DIR, "index.html")))

      def asset(_req, path:)
        full = File.expand_path(path, WEB_DIR)
        raise NotFound, path unless full.start_with?("#{WEB_DIR}/") && File.file?(full)

        Http::Response.new(200, MIME.fetch(File.extname(full), "application/octet-stream"), File.read(full))
      end

      IMAGE_TYPES = { ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".webp" => "image/webp", ".svg" => "image/svg+xml" }.freeze
      # Only design targets and the last diff leave the course folder. Never the solution or state.
      SERVABLE = %r{\Acourse/(tests/[\w.-]+/target\.\w+|design/[\w./-]+|\.cache/diff-[\w.-]+\.png)\z}

      def course_file(_req, course:, path:)
        c = load_course(course)
        rel = path.to_s
        raise NotFound, rel unless rel.match?(SERVABLE) && !rel.include?("..") && IMAGE_TYPES.key?(File.extname(rel).downcase)

        full = File.expand_path(rel, c.dir)
        raise NotFound, rel unless full.start_with?("#{c.dir}/") && File.file?(full)

        Http::Response.new(200, IMAGE_TYPES.fetch(File.extname(full).downcase), File.binread(full))
      end

      def courses(_req)
        list = @config.course_dirs.filter_map do |dir|
          c = Course.load(dir)
          next unless c.status == "compiled"

          state = State.load(c.state_path)
          cur = Status.current_lesson(c.outline, state)
          { "slug" => c.slug, "title" => c.title, "progress" => Status.progress(c.outline, state),
            "current" => cur && { "id" => cur.id, "title" => cur.title } }
        end
        Http.json(200, { "courses" => list })
      end

      def course_map(_req, course:)
        c = load_course(course)
        state = State.load(c.state_path)
        lessons = c.outline.map do |l|
          { "id" => l.id, "title" => l.title, "track" => l.track, "status" => Status.lesson(c.outline, state, l.id),
            "steps" => l.steps.map { |s| { "id" => s.id, "title" => s.title, "status" => Status.step(c.outline, state, s.id) } } }
        end
        Http.json(200, { "slug" => c.slug, "title" => c.title, "progress" => Status.progress(c.outline, state), "lessons" => lessons })
      end

      def lesson(_req, course:, lesson:)
        c = load_course(course)
        l = load_lesson(c, lesson)
        state = State.load(c.state_path)
        status = Status.lesson(c.outline, state, l.id)
        return Http.json(403, { "error" => status == :building ? "this lesson is still being written" : "lesson is locked", "status" => status }) if %i[locked building].include?(status)

        Http.json(200, lesson_view(c, l, state, status))
      end

      def lesson_view(c, l, state, status)
        blocked = @config.blocklist
        resources = l.resources.map { |r| r.to_h.transform_keys(&:to_s).merge("blocked" => blocked.include?(r.url)) }
        i = c.outline.index { _1.id == l.id }
        { "course" => c.slug, "id" => l.id, "title" => l.title, "track" => l.track, "goal" => l.goal, "status" => status,
          "sections" => l.sections.transform_keys(&:to_s),
          "steps" => l.steps.map { step_view(c, _1, state) },
          "resources" => resources, "resource" => resources.find { !_1["blocked"] },
          "concepts" => l.concepts.map { |s| { "slug" => s, "exists" => File.exist?(@config.concept_path(s)) } },
          "solution_unlocked" => Status.solution_unlocked?(c.outline, state, l.id),
          "next_lesson" => c.outline[i + 1]&.id }
      end

      def step_view(c, s, state)
        revealed = Status.hints_revealed(state, s.id)
        tests = Checks.test_files(c, s).map { |f| { "path" => f.delete_prefix("#{c.dir}/"), "code" => File.read(f) } }
        { "id" => s.id, "title" => s.title, "kind" => s.kind, "verify" => s.verify, "generators" => s.generators,
          "instructions" => s.instructions, "gotchas" => s.gotchas, "status" => Status.step(c.outline, state, s.id),
          "attempts" => state.dig("steps", s.id, "attempts") || 0, "last_exit" => state.dig("steps", s.id, "last_exit"),
          "hints" => s.hints.first(revealed), "hints_total" => s.hints.size, "tests" => tests,
          "design" => (s.kind == "visual" ? image_url(c, "course/tests/#{s.id}/target.png") : nil),
          "diff" => (s.kind == "visual" ? image_url(c, "course/.cache/diff-#{s.id}.png") : nil) }
      end

      def image_url(c, rel) = File.file?(File.join(c.dir, rel)) ? "/api/courses/#{c.slug}/files/#{rel}" : nil

      def verify(_req, course:, step:)
        c, l, s = load_step(course, step)
        store = store_for(c)
        return locked_step(s) if Status.step(c.outline, store.read, s.id) == :locked

        lock = @guard.synchronize { @verify_locks[c.dir] }
        return Http.json(409, { "error" => "a verify is already running for this course" }) unless lock.try_lock

        Http::Sse.new(lambda { |emit|
          begin
            log_path = verify_log(c, s.id)
            FileUtils.mkdir_p(File.dirname(log_path))
            was_green = Status.lesson(c.outline, store.read, l.id) == :green
            code = File.open(log_path, "w") do |log|
              Shell.stream(s.verify, cwd: c.dir, env: { "BYOX_STEP" => s.id, "BYOX_BIN" => BIN }) do |line|
                log.write(line)
                emit.call("line", { "text" => line })
              end
            end
            state = store.apply({ "type" => "verify", "step" => s.id, "exit" => code })
            lesson_status = Status.lesson(c.outline, state, l.id)
            emit.call("done", { "ok" => code.zero?, "exit" => code, "step_status" => Status.step(c.outline, state, s.id),
                                "lesson_status" => lesson_status, "lesson_green" => !was_green && lesson_status == :green })
          ensure
            lock.unlock
          end
        })
      end

      def hint(_req, course:, step:, n:)
        c, _l, s = load_step(course, step)
        store = store_for(c)
        state = store.read
        return locked_step(s) if Status.step(c.outline, state, s.id) == :locked

        n = n.to_i
        revealed = Status.hints_revealed(state, s.id)
        return Http.json(400, { "error" => "hint must be 1 to #{s.hints.size}" }) unless n.between?(1, s.hints.size)
        return Http.json(409, { "error" => "reveal hint #{revealed + 1} first", "revealed" => revealed }) if n > revealed + 1

        store.apply({ "type" => "hint", "step" => s.id, "n" => n }) if n > revealed
        shown = [n, revealed].max
        Http.json(200, { "step" => s.id, "revealed" => shown, "hints" => s.hints.first(shown) })
      end

      def skip(_req, course:, lesson:)
        c = load_course(course)
        l = load_lesson(c, lesson)
        store = store_for(c)
        return Http.json(409, { "error" => "lesson is locked" }) if Status.lesson(c.outline, store.read, l.id) == :locked

        state = store.apply({ "type" => "skip", "lesson" => l.id })
        nxt = Status.current_lesson(c.outline, state)
        Http.json(200, { "status" => Status.lesson(c.outline, state, l.id), "next_lesson" => nxt&.id })
      end

      def solution(_req, course:, lesson:)
        c, l, store = unlocked(course, lesson) { return _1 }
        store.apply({ "type" => "solution", "lesson" => l.id }) unless store.read.dig("lessons", l.id, "solution_unlocked_at")
        steps = l.steps.map do |s|
          original = File.join(c.course_dir, "source", "diffs", "#{s.id}.diff")
          { "id" => s.id, "title" => s.title, "files" => Solution.step_diff(c, s).map { _1.to_h.transform_keys(&:to_s) },
            "original" => File.exist?(original) ? File.read(original) : nil }
        end
        Http.json(200, { "lesson" => l.id, "steps" => steps })
      end

      def compare(_req, course:, lesson:)
        c, l, = unlocked(course, lesson) { return _1 }
        Http.json(200, { "lesson" => l.id, "files" => Solution.compare(c, l).map { _1.to_h.transform_keys(&:to_s) } })
      end

      def unlocked(course, lesson)
        c = load_course(course)
        l = load_lesson(c, lesson)
        store = store_for(c)
        yield Http.json(403, { "error" => "the solution unlocks when the lesson is green or skipped" }) unless Status.solution_unlocked?(c.outline, store.read, l.id)
        [c, l, store]
      end

      def explain(_req, course:, step:)
        c, l, s = load_step(course, step)
        log = verify_log(c, s.id)
        return Http.json(409, { "error" => "run Verify first" }) unless File.exist?(log)

        store_for(c).apply({ "type" => "feedback", "kind" => "explain", "lesson" => l.id, "step" => s.id })
        agent_job(c.dir, :explain, JobInput.new(course: c, config: @config, lesson: l, step: s, section: nil, note: nil,
                                                 failure_path: log, target: l.path))
      end

      def unclear(req, course:, lesson:)
        c = load_course(course)
        l = load_lesson(c, lesson)
        section, note = req.body.values_at("section", "note").map(&:to_s)
        return Http.json(400, { "error" => "section and note are required" }) if section.empty? || note.strip.empty?

        store_for(c).apply({ "type" => "feedback", "kind" => "unclear", "lesson" => l.id, "section" => section, "note" => note })
        agent_job(c.dir, :unclear, JobInput.new(course: c, config: @config, lesson: l, step: nil, section:, note:,
                                                 failure_path: nil, target: l.path))
      end

      def broken(req, course:, lesson:)
        c = load_course(course)
        l = load_lesson(c, lesson)
        note = req.body["note"].to_s
        step = l.steps.find { _1.id == req.body["step"].to_s }
        log = step && verify_log(c, step.id)
        store_for(c).apply({ "type" => "feedback", "kind" => "broken", "lesson" => l.id, "step" => step&.id, "note" => note })
        agent_job(c.dir, :broken, JobInput.new(course: c, config: @config, lesson: l, step:, section: nil, note:,
                                               failure_path: log && File.exist?(log) ? log : nil, target: l.path))
      end

      def bad_resource(req, course:, lesson:)
        c = load_course(course)
        l = load_lesson(c, lesson)
        url = req.body["url"].to_s
        return Http.json(400, { "error" => "not a resource of this lesson" }) unless l.resources.any? { _1.url == url }

        unless @config.blocklist.include?(url)
          FileUtils.mkdir_p(@config.vault)
          File.open(@config.blocklist_path, "a") { _1.puts("- #{url} | #{State.now} | #{c.slug}/#{l.id}") }
        end
        store_for(c).apply({ "type" => "feedback", "kind" => "bad_resource", "lesson" => l.id, "url" => url })
        view = lesson_view(c, l, State.load(c.state_path), nil)
        Http.json(200, { "resource" => view["resource"], "resources" => view["resources"] })
      end

      def concept(_req, slug:)
        raise NotFound, "no concept #{slug}" unless slug.match?(/\A[a-z0-9-]+\z/) && File.exist?(@config.concept_path(slug))

        page = Concept.parse(@config.concept_path(slug))
        where = @config.course_dirs.flat_map do |dir|
          c = Course.load(dir)
          c.outline.filter_map do |o|
            l = c.lesson(o.id)
            { "course" => c.slug, "lesson" => l.id, "title" => l.title } if l.concepts.include?(slug)
          rescue FormatError, Errno::ENOENT
            nil
          end
        end
        Http.json(200, { "slug" => slug, "title" => page.title, "body" => page.body, "where" => where })
      end

      def unclear_concept(req, slug:)
        raise NotFound, "no concept #{slug}" unless slug.match?(/\A[a-z0-9-]+\z/) && File.exist?(@config.concept_path(slug))

        section, note = req.body.values_at("section", "note").map(&:to_s)
        return Http.json(400, { "error" => "section and note are required" }) if section.empty? || note.strip.empty?

        agent_job(@config.concepts_dir, :unclear_concept, JobInput.new(course: nil, config: @config, lesson: nil, step: nil, section:,
                                                                       note:, failure_path: nil, target: @config.concept_path(slug)))
      end

      def add_lessons(req, course:)
        c = load_course(course)
        request = req.body["request"].to_s.strip
        return Http.json(400, { "error" => "say what to add, such as a source or the next chapters" }) if request.empty?

        agent_job(c.dir, :add_lessons, JobInput.new(course: c, config: @config, lesson: nil, step: nil, section: nil, note: request,
                                                    failure_path: nil, target: nil))
      end

      def feedback_list(_req) = Http.json(200, { "items" => Feedback.all(@config).map(&:to_h), "changes" => Feedback.changes(@config) })

      def feedback_upload(_req)
        changes = Feedback.changes(@config)
        return Http.json(409, { "error" => "set plugin_repo in byox.yml to your byox checkout first" }) if changes.nil?
        return Http.json(409, { "error" => "your byox checkout has no changes to upload" }) if changes.zero?

        agent_job(:feedback, :feedback_upload, JobInput.new(course: nil, config: @config, lesson: nil, step: nil, section: nil,
                                                            note: nil, failure_path: nil, target: nil))
      end

      def feedback_add(req)
        item = Feedback.add(@config, text: req.body["text"], page: req.body["page"])
        Http.json(200, { "item" => item.to_h, "open" => Feedback.open(@config).size })
      rescue ArgumentError => e
        Http.json(400, { "error" => e.message })
      end

      def feedback_ship(_req)
        return Http.json(409, { "error" => "there is no open feedback to ship" }) if Feedback.open(@config).empty?

        agent_job(:feedback, :feedback, JobInput.new(course: nil, config: @config, lesson: nil, step: nil, section: nil,
                                                     note: nil, failure_path: nil, target: nil))
      end

      # One agent job at a time per course, and one for the shared concept library.
      def agent_job(key, kind, input)
        lock = @guard.synchronize { @job_locks[key] }
        return Http.json(409, { "error" => "an agent job is already running for this course" }) unless lock.try_lock

        Http::Sse.new(lambda { |emit|
          begin
            emit.call("done", AgentJobs.run(kind, input) { |ev, data| emit.call(ev, data) })
          ensure
            lock.unlock
          end
        })
      end

      def load_course(slug)
        dir = File.join(@config.root, slug)
        raise NotFound, "no course #{slug}" unless slug.match?(/\A[\w.-]+\z/) && File.exist?(File.join(dir, "course", "course.md"))

        Course.load(dir)
      end

      def load_lesson(c, id)
        raise NotFound, "no lesson #{id}" unless c.outline_lesson(id)

        c.lesson(id)
      end

      def load_step(course, step)
        c = load_course(course)
        o = c.lesson_of_step(step) or raise NotFound, "no step #{step}"
        l = c.lesson(o.id)
        [c, l, l.steps.find { _1.id == step } || raise(NotFound, "no step #{step}")]
      end

      def locked_step(s) = Http.json(409, { "error" => "step #{s.id} is locked. Finish the step before it." })
      def verify_log(c, id) = File.join(c.course_dir, ".cache", "verify", "#{id}.log")
      def store_for(c) = Store.new(c, on_change: ->(state) { CourseNote.write(@config, c, state) })
    end
  end
end
