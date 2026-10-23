# frozen_string_literal: true

# The only reader of course files. The site, lint, strength and the CLI all parse
# through here, so the on-disk format has exactly one definition.
module Byox
  class FormatError < StandardError
    attr_reader :path, :problems # [[check, message]]

    def initialize(path, problems)
      @path = path
      @problems = problems
      super(problems.map { |check, msg| "#{path}: #{check}: #{msg}" }.join("\n"))
    end
  end

  STEP_ID = /\A\d{2}\.\d+\z/
  KINDS = %w[backend cli ui visual cloud perf stub].freeze
  SECTIONS = { "Short read" => :short_read, "Task" => :task, "Tests in plain English" => :tests }.freeze
  # A "Gotchas" section is no longer written, so it is not required. Older pages that have it still match in order.
  CONCEPT_HEADINGS = ["The problem", "How it works", "A tiny example", "What ", "Diagrams"].freeze

  Resource = Data.define(:url, :section, :why)

  Step = Data.define(:id, :title, :kind, :verify, :generators, :generated, :instructions, :gotchas, :hints, :fixed_values, :design_url) do
    def tag = "step-#{id}"
    def tests_dir = "course/tests/#{id}"
  end

  Lesson = Data.define(:id, :title, :track, :goal, :concepts, :resources, :steps, :sections, :path)

  # One folder of the learner's work: path is under work/, source is where it lives in the
  # solution repo ("." is the repo root).
  Project = Data.define(:name, :path, :source, :description)

  OutlineStep = Data.define(:id, :title)
  OutlineLesson = Data.define(:id, :title, :track, :steps, :building)

  Concept = Data.define(:slug, :title, :body, :path)

  Course = Data.define(:slug, :title, :status, :dir, :meta, :outline) do
    def course_dir = File.join(dir, "course")

    # "split": the project folder holds course/ for the agent and work/ for the learner.
    # "inline" is the older layout, where the learner's app is the project folder itself.
    def layout = meta["layout"] == "split" ? "split" : "inline"
    def work_dir = File.join(dir, "work")

    # A course with no `projects:` has one project, work/ itself. Declared projects are
    # folders inside work/, and the first is the main one, where verify runs.
    def multi? = !Array(meta["projects"]).empty?

    def projects
      return [Project.new(name: "work", path: ".", source: ".", description: nil)] unless multi?

      Array(meta["projects"]).map do |p|
        name = p["name"].to_s
        Project.new(name:, path: (p["path"] || name).to_s, source: (p["source"] || name).to_s, description: p["description"])
      end
    end

    def project_dir(project, work = work_dir) = File.expand_path(project.path, work)
    def app_dir = layout == "split" ? project_dir(projects.first) : dir

    # What a verify script is told about the layout. work overrides the work folder, for a
    # temporary export of a solution tag.
    def project_env(work = work_dir)
      return { "BYOX_COURSE" => course_dir } unless layout == "split"

      projects.each_with_object({ "BYOX_COURSE" => course_dir, "BYOX_WORK" => work }) do |p, env|
        env["BYOX_PROJECT_#{p.name.upcase.gsub(/[^A-Z0-9]/, '_')}"] = project_dir(p, work)
      end
    end
    def lesson_path(id) = File.join(course_dir, "lessons", "#{id}.md")
    def solution_dir = File.join(course_dir, "solution")
    def state_path = File.join(course_dir, "state.json")
    def lessons = outline.map { |l| Lesson.parse(lesson_path(l.id)) }
    def lesson(id) = Lesson.parse(lesson_path(id))
    def step_ids = outline.flat_map { |l| l.steps.map(&:id) }
    def outline_lesson(id) = outline.find { |l| l.id == id }
    def lesson_of_step(step_id) = outline.find { |l| l.steps.any? { |s| s.id == step_id } }

    def previous_tag(step_id)
      i = step_ids.index(step_id) or raise ArgumentError, "unknown step #{step_id}"
      i.zero? ? "base" : "step-#{step_ids[i - 1]}"
    end

    def self.load(dir)
      path = File.join(dir, "course", "course.md")
      meta, = Format.split_front_matter(path)
      outline = Array(meta["lessons"]).map do |l|
        steps = Array(l["steps"]).map { |s| OutlineStep.new(id: s["id"].to_s, title: s["title"].to_s) }
        OutlineLesson.new(id: l["id"].to_s, title: l["title"].to_s, track: (l["track"] || "core").to_s, steps:, building: l["building"] == true)
      end
      new(slug: File.basename(dir), title: meta["title"].to_s, status: meta["status"].to_s,
          dir: File.expand_path(dir), meta:, outline:)
    end
  end

  class Lesson
    def self.parse(path)
      meta, body = Format.split_front_matter(path)
      problems = []
      id = meta["id"].to_s
      problems << [:front_matter, "id must match the file name"] unless File.basename(path, ".md") == id
      problems << [:sections_present, "goal is empty"] if meta["goal"].to_s.strip.empty?
      sections = Format.h2_sections(body, problems)
      steps = Array(meta["steps"]).map { |s| Format.step(s, id, problems) }
      problems << [:front_matter, "no steps"] if steps.empty?
      raise FormatError.new(path, problems) unless problems.empty?

      resources = Array(meta["resources"]).map do |r|
        Resource.new(url: r["url"].to_s, section: r["section"].to_s, why: r["why"].to_s)
      end
      new(id:, title: meta["title"].to_s, track: (meta["track"] || "core").to_s, goal: meta["goal"].to_s.strip,
          concepts: Array(meta["concepts"]).map(&:to_s), resources:, steps:, sections:, path:)
    end
  end

  class Concept
    def self.parse(path)
      meta, body = Format.split_front_matter(path)
      new(slug: File.basename(path, ".md"), title: (meta["title"] || File.basename(path, ".md")).to_s, body:, path:)
    end

    def missing_headings
      found = body.scan(/^## (.+)$/).flatten
      pos = 0
      CONCEPT_HEADINGS.reject do |want|
        at = found[pos..].index { |h| h.start_with?(want) }
        at && (pos += at + 1)
      end.map(&:strip)
    end
  end

  module Format
    module_function

    def split_front_matter(path)
      text = File.read(path)
      m = text.match(/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m)
      raise FormatError.new(path, [[:front_matter, "missing YAML front matter"]]) unless m

      meta = YAML.safe_load(m[1], permitted_classes: [Date, Time]) || {}
      raise FormatError.new(path, [[:front_matter, "front matter is not a mapping"]]) unless meta.is_a?(Hash)

      [meta, m[2]]
    rescue Psych::SyntaxError => e
      raise FormatError.new(path, [[:front_matter, "YAML: #{e.message}"]])
    end

    def h2_sections(body, problems)
      parts = body.split(/^## (.+)\n/)
      found = parts.drop(1).each_slice(2).to_h { |name, text| [name.strip, text.to_s.strip] }
      (found.keys - SECTIONS.keys).each { problems << [:sections_present, "unknown section '#{_1}'"] }
      SECTIONS.to_h do |name, key|
        problems << [:sections_present, "section '#{name}' is missing or empty"] if found[name].to_s.empty?
        [key, found[name].to_s]
      end
    end

    def step(raw, lesson_id, problems)
      raw = {} unless raw.is_a?(Hash)
      id = raw["id"].to_s
      where = "step #{id.empty? ? '?' : id}"
      problems << [:front_matter, "#{where}: id must look like NN.k"] unless id.match?(STEP_ID)
      problems << [:front_matter, "#{where}: id must start with the lesson number"] unless id.start_with?(lesson_id[0, 2])
      %w[title verify].each { |f| problems << [:front_matter, "#{where}: #{f} is empty"] if raw[f].to_s.strip.empty? }
      problems << [:front_matter, "#{where}: kind must be one of #{KINDS.join(', ')}"] unless KINDS.include?(raw["kind"].to_s)
      problems << [:sections_present, "#{where}: instructions are empty"] if raw["instructions"].to_s.strip.empty?
      design_url = raw["design_url"].to_s.strip
      problems << [:front_matter, "#{where}: design_url must be an https link"] unless design_url.empty? || design_url.match?(%r{\Ahttps://\S+\z})
      hints = Array(raw["hints"]).map(&:to_s)
      problems << [:three_hints, "#{where}: has #{hints.size} hints, needs 3"] unless hints.size == 3 && hints.none? { _1.strip.empty? }
      Step.new(id:, title: raw["title"].to_s, kind: raw["kind"].to_s, verify: raw["verify"].to_s,
               generators: Array(raw["generators"]).map(&:to_s), generated: Array(raw["generated"]).map(&:to_s),
               instructions: raw["instructions"].to_s, gotchas: raw["gotchas"].to_s, hints:,
               fixed_values: raw["fixed_values"].to_s.strip, design_url: (design_url.empty? ? nil : design_url))
    end

    def generated?(path, globs)
      globs.any? do |g|
        next true if g == "**"

        g.end_with?("/**") ? path.start_with?(g.delete_suffix("**")) : File.fnmatch?(g, path, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
      end
    end
  end
end
