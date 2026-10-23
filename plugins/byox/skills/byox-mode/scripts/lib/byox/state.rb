# frozen_string_literal: true

# course/state.json holds facts only. Every status (locked, open, green, current
# lesson, weakness log) is a pure function over (outline, state).
#
#   {"byox": 1,
#    "steps":   {"01.1": {"passed_at": t, "attempts": 3, "hints_revealed": 1, "last_exit": 0}},
#    "lessons": {"01-ping": {"skipped_at": t, "solution_unlocked_at": t}},
#    "feedback": [{"at": t, "kind": "explain|unclear|broken|bad_resource", "lesson": id, ...}]}
module Byox
  module State
    module_function

    def empty = { "byox" => 1, "steps" => {}, "lessons" => {}, "feedback" => [] }

    def load(path)
      File.exist?(path) ? empty.merge(JSON.parse(File.read(path))) : empty
    end

    def now = Time.now.utc.iso8601

    # Pure: (state, event) -> new state. Events are plain hashes with a "type".
    def reduce(state, event)
      s = JSON.parse(JSON.generate(state))
      case event.fetch("type")
      when "verify"
        f = (s["steps"][event.fetch("step")] ||= {})
        f["attempts"] = f.fetch("attempts", 0) + 1
        f["last_exit"] = event.fetch("exit")
        f["passed_at"] ||= event.fetch("at") if event.fetch("exit").zero?
      when "hint"
        f = (s["steps"][event.fetch("step")] ||= {})
        f["hints_revealed"] = [f.fetch("hints_revealed", 0), event.fetch("n")].max
      when "skip"
        (s["lessons"][event.fetch("lesson")] ||= {})["skipped_at"] ||= event.fetch("at")
      when "solution"
        (s["lessons"][event.fetch("lesson")] ||= {})["solution_unlocked_at"] ||= event.fetch("at")
      when "feedback"
        s["feedback"] << event.except("type")
      else
        raise ArgumentError, "unknown event #{event['type']}"
      end
      s
    end
  end

  module Status
    module_function

    def step_green?(state, id) = !state.dig("steps", id, "passed_at").nil?
    def hints_revealed(state, id) = state.dig("steps", id, "hints_revealed") || 0

    def lesson(outline, state, id)
      i = outline.index { _1.id == id } or raise ArgumentError, "unknown lesson #{id}"
      l = outline[i]
      return :building if l.building
      return :green if l.steps.all? { step_green?(state, _1.id) }
      return :skipped if state.dig("lessons", id, "skipped_at")
      return :open if i.zero?

      %i[green skipped].include?(lesson(outline, state, outline[i - 1].id)) ? :open : :locked
    end

    # Steps unlock in order inside an open lesson.
    def step(outline, state, id)
      l = outline.find { |x| x.steps.any? { _1.id == id } } or raise ArgumentError, "unknown step #{id}"
      return :locked if %i[locked building].include?(lesson(outline, state, l.id))
      return :green if step_green?(state, id)

      i = l.steps.index { _1.id == id }
      i.zero? || step_green?(state, l.steps[i - 1].id) ? :open : :locked
    end

    def solution_unlocked?(outline, state, id) = %i[green skipped].include?(lesson(outline, state, id))
    def current_lesson(outline, state) = outline.find { lesson(outline, state, _1.id) == :open }

    def progress(outline, state)
      ids = outline.flat_map { |l| l.steps.map(&:id) }
      { "done" => ids.count { step_green?(state, _1) }, "total" => ids.size }
    end

    def weaknesses(outline, state)
      title = outline.to_h { [_1.id, _1.title] }
      skipped = outline.select { lesson(outline, state, _1.id) == :skipped }.map { "Skipped #{_1.id} #{_1.title}." }
      steps = state["steps"].sort.flat_map do |id, f|
        [("Used all 3 hints on #{id}." if f["hints_revealed"].to_i >= 3),
         ("#{f['attempts']} verify attempts on #{id}." if f["attempts"].to_i >= 5)].compact
      end
      notes = state["feedback"].map do |f|
        case f["kind"]
        when "explain" then "Asked for an explanation on #{f['step']}."
        when "unclear" then "Marked #{f['section']} of #{title[f['lesson']] || f['lesson']} unclear: \"#{f['note']}\""
        when "broken" then "Reported #{f['lesson']} as broken: \"#{f['note']}\""
        when "bad_resource" then "Flagged a resource on #{f['lesson']}: #{f['url']}"
        end
      end
      skipped + steps + notes.compact
    end
  end

  # The single writer of state.json. A process-wide mutex per file serializes writers
  # in the site; the site's flock on <root>/.byox/site.lock keeps other processes out.
  class Store
    LOCKS = Hash.new { |h, k| h[k] = Mutex.new }
    LOCKS_GUARD = Mutex.new

    def initialize(course, on_change: nil)
      @course = course
      @on_change = on_change
      @lock = LOCKS_GUARD.synchronize { LOCKS[course.state_path] }
    end

    def read = State.load(@course.state_path)

    def apply(event)
      @lock.synchronize do
        state = State.reduce(read, { "at" => State.now }.merge(event))
        tmp = "#{@course.state_path}.#{Process.pid}.tmp"
        File.write(tmp, JSON.pretty_generate(state))
        File.rename(tmp, @course.state_path)
        @on_change&.call(state)
        state
      end
    end
  end

  module CourseNote
    module_function

    def render(course, state)
      outline = course.outline
      p = Status.progress(outline, state)
      cur = Status.current_lesson(outline, state)
      rows = outline.map do |l|
        done = l.steps.count { Status.step_green?(state, _1.id) }
        hints = l.steps.sum { Status.hints_revealed(state, _1.id) }
        fails = l.steps.sum { (state.dig("steps", _1.id, "attempts") || 0) - (Status.step_green?(state, _1.id) ? 1 : 0) }
        "| #{l.id} #{l.title} | #{Status.lesson(outline, state, l.id)} | #{done}/#{l.steps.size} | #{hints} | #{fails} |"
      end
      weak = Status.weaknesses(outline, state)
      <<~MD
        <!-- Generated by byox from course/state.json. Edits here are overwritten. -->
        # #{course.title}

        Progress: #{p['done']} of #{p['total']} steps. Current: #{cur ? "#{cur.id} #{cur.title}" : 'none'}.

        ## Course map

        | Lesson | Status | Steps | Hints | Failed verifies |
        |---|---|---|---|---|
        #{rows.join("\n")}

        ## Weakness log

        #{weak.empty? ? 'Nothing yet.' : weak.map { "- #{_1}" }.join("\n")}
      MD
    end

    def write(config, course, state)
      FileUtils.mkdir_p(config.courses_note_dir)
      path = File.join(config.courses_note_dir, "#{course.slug}.md")
      tmp = "#{path}.tmp"
      File.write(tmp, render(course, state))
      File.rename(tmp, path)
      path
    end
  end
end
