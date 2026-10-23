# frozen_string_literal: true

require "net/http"
require "uri"

# Scripted checks that replace agent judgment. Each finding prints as one TSV row:
# check, where, message.
module Byox
  Finding = Data.define(:check, :where, :message) do
    def to_s = [check, where, message].join("\t")
  end

  StrengthRow = Data.define(:step, :prev_exit, :this_exit, :verdict) do
    def to_s = [step, prev_exit, this_exit, verdict].join("\t")
  end

  module Checks
    module_function

    RANDOM = /SecureRandom|\brand\b|\bRandom\b|Faker|random|uuid|\$RANDOM|urandom|shuf\b/i
    LINK = %r{\]\((https?://[^)\s]+)\)}

    def lint(course, config, lesson: nil, offline: false)
      ids = lesson ? [lesson] : course.outline.map(&:id)
      findings = ids.flat_map { lint_lesson(course, config, _1, offline:) }
      findings += outline_matches_files(course) + project_findings(course) unless lesson
      findings
    end

    def lint_lesson(course, config, id, offline:)
      path = course.lesson_path(id)
      return [Finding.new(:outline_matches_files, id, "lesson file #{path} is missing")] unless File.exist?(path)

      l = Lesson.parse(path)
      [*outline_matches_lesson(course, l), *tests_exist(course, l), *random_values_in_tests(course, l),
       *hint3_no_solution(course, l), *no_solution_leak(course, l), *resources(config, l),
       *links_resolve(l, offline:), *concept_pages(config, l), *project_refs(course, l)]
    rescue FormatError => e
      e.problems.map { |check, msg| Finding.new(check, id, msg) }
    end

    PROJECT_NAME = /\A[a-z][a-z0-9_-]*\z/

    def project_findings(course)
      return [] unless course.multi?

      seen = {}
      course.projects.flat_map do |p|
        out = []
        out << Finding.new(:projects, "course.md", "project name #{p.name.inspect} must be lowercase letters, digits, - or _") unless p.name.match?(PROJECT_NAME)
        out << Finding.new(:projects, "course.md", "duplicate project name #{p.name}") if seen[p.name]
        seen[p.name] = true
        unless safe_relative?(p.path)
          out << Finding.new(:projects, "course.md", "project #{p.name} path #{p.path} must stay inside work/")
        end
        unless safe_relative?(p.source)
          out << Finding.new(:projects, "course.md", "project #{p.name} source #{p.source} must stay inside the solution repo")
        end
        out
      end
    end

    def safe_relative?(path) = !path.start_with?("/") && !path.split("/").include?("..")

    # A verify command or script may only name projects the course declares.
    def project_refs(course, lesson)
      return [] unless course.multi?

      declared = course.projects.map { _1.name.upcase.gsub(/[^A-Z0-9]/, "_") }
      lesson.steps.flat_map do |s|
        files = s.verify.scan(%r{(?:\$BYOX_COURSE|course)/(verify/[^\s"']+)}).flatten.map { File.join(course.course_dir, _1) }
        text = [s.verify, *files.select { File.file?(_1) }.map { File.read(_1) }].join("\n")
        text.scan(/\$\{?BYOX_PROJECT_([A-Z0-9_]+)/).flatten.uniq.reject { declared.include?(_1) }.map do |name|
          Finding.new(:projects, s.id, "#{s.id} verify uses $BYOX_PROJECT_#{name}, but course.md declares #{course.projects.map(&:name).join(', ')}")
        end
      end
    end

    def outline_matches_lesson(course, lesson)
      o = course.outline_lesson(lesson.id)
      return [Finding.new(:outline_matches_files, lesson.id, "lesson is not in course.md")] unless o

      want = [o.title, o.steps.map { [_1.id, _1.title] }]
      got = [lesson.title, lesson.steps.map { [_1.id, _1.title] }]
      want == got ? [] : [Finding.new(:outline_matches_files, lesson.id, "course.md says #{want.inspect}, lesson says #{got.inspect}")]
    end

    def outline_matches_files(course)
      files = Dir[File.join(course.course_dir, "lessons", "*.md")].map { File.basename(_1, ".md") }
      (files - course.outline.map(&:id)).map { Finding.new(:outline_matches_files, _1, "lesson file is not in course.md") }
    end

    def tests_exist(course, lesson)
      lesson.steps.flat_map do |s|
        files = test_files(course, s)
        named = s.verify.scan(%r{course/[^\s"']+}) + s.verify.scan(%r{\$BYOX_COURSE/([^\s"']+)}).flatten.map { "course/#{_1}" }
        missing = named.reject { File.exist?(File.join(course.dir, _1)) }
        [(Finding.new(:tests_exist, s.id, "no files in #{s.tests_dir}") if files.empty? && s.kind != "cloud"),
         *missing.map { Finding.new(:tests_exist, s.id, "verify names #{_1}, which does not exist") }].compact
      end
    end

    def random_values_in_tests(course, lesson)
      lesson.steps.filter_map do |s|
        files = test_files(course, s)
        next if s.kind == "cloud" || !s.fixed_values.empty? || files.empty? || files.any? { File.read(_1).match?(RANDOM) }

        Finding.new(:random_values_in_tests, s.id, "tests use no random values, so a hardcoded answer could pass")
      end
    end

    def hint3_no_solution(course, lesson)
      lesson.steps.flat_map do |s|
        leaked(course, s).select { s.hints[2].include?(_1) }
                         .map { Finding.new(:hint3_no_solution, s.id, "hint 3 contains solution line: #{_1}") }
      end
    end

    def no_solution_leak(course, lesson)
      prose = [*lesson.sections.values, lesson.goal, *lesson.steps.flat_map { [_1.instructions, _1.gotchas, *_1.hints.first(2)] }].join("\n")
      lesson.steps.flat_map do |s|
        leaked(course, s).select { prose.include?(_1) }
                         .map { Finding.new(:no_solution_leak, s.id, "prose contains solution line: #{_1}") }
      end
    end

    def leaked(course, step)
      return [] unless Solution.tag?(course, step.tag)

      Solution.added_lines(course, step)
    end

    def resources(config, lesson)
      blocked = config.blocklist
      out = []
      out << Finding.new(:resources, lesson.id, "needs 2 resources, has #{lesson.resources.size}") unless lesson.resources.size == 2
      lesson.resources.each do |r|
        out << Finding.new(:resources, lesson.id, "#{r.url} is on the blocklist") if blocked.include?(r.url)
        out << Finding.new(:resources, lesson.id, "#{r.url} has no section") if r.section.strip.empty?
      end
      out
    end

    def links_resolve(lesson, offline:)
      urls = (lesson.resources.map(&:url) + lesson.sections.values.join("\n").scan(LINK).flatten).uniq
      urls.filter_map do |url|
        problem = link_problem(url, offline:)
        Finding.new(:links_resolve, lesson.id, "#{url}: #{problem}") if problem
      end
    end

    def link_problem(url, offline:, hops: 5)
      uri = URI.parse(url)
      return "not an http(s) URL" unless uri.is_a?(URI::HTTP) && uri.host
      return nil if offline

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 10) do |h|
        h.request(Net::HTTP::Get.new(uri, "User-Agent" => "byox-lint"))
      end
      return link_problem(URI.join(url, res["location"]).to_s, offline:, hops: hops - 1) if res.is_a?(Net::HTTPRedirection) && hops.positive?

      res.code.to_i.between?(200, 299) ? nil : "HTTP #{res.code}"
    rescue URI::InvalidURIError
      "not a valid URL"
    rescue StandardError => e
      "#{e.class}: #{e.message}"
    end

    def concept_pages(config, lesson)
      lesson.concepts.flat_map do |slug|
        path = config.concept_path(slug)
        next [Finding.new(:concept_pages, lesson.id, "concept page #{slug} is missing")] unless File.exist?(path)

        Concept.parse(path).missing_headings.map { Finding.new(:concept_pages, slug, "missing or out-of-order heading '#{_1}'") }
      end
    end

    BINARY = %w[.png .jpg .jpeg .webp .gif .ico].freeze

    # Test code only. A visual step keeps its target image here, which is not code.
    def test_files(course, step)
      Dir[File.join(course.dir, step.tests_dir, "**", "*")].select { File.file?(_1) && !BINARY.include?(File.extname(_1).downcase) }
    end

    # Each step's verify must fail on the solution at the previous tag and pass at its own
    # tag. Both trees are exported to temp dirs with `course/` symlinked in, so the
    # solution repo is never touched.
    def strength(course, lesson: nil, step: nil)
      lessons = lesson ? [course.lesson(lesson)] : course.lessons
      lessons.flat_map(&:steps).select { step.nil? || _1.id == step }.map { strength_step(course, _1) }
    end

    def strength_step(course, step)
      return StrengthRow.new(step.id, "-", "-", "exempt") if step.kind == "cloud"
      return StrengthRow.new(step.id, "-", "-", "missing tag") unless Solution.tag?(course, step.tag)

      prev_exit, this_exit = [course.previous_tag(step.id), step.tag].map do |tag|
        Dir.mktmpdir("byox-strength-") do |tmp|
          Solution.export_work(course, tag, tmp)
          File.symlink(course.course_dir, File.join(tmp, "course")) unless course.layout == "split"
          env = { "BYOX_STEP" => step.id, "BYOX_BIN" => BIN }.merge(course.project_env(tmp))
          cwd = course.layout == "split" ? course.project_dir(course.projects.first, tmp) : tmp
          Shell.capture(step.verify, cwd:, env:, timeout: 300).first
        end
      end
      verdict = if this_exit != 0 then "broken"
                elsif prev_exit.zero? then "weak"
                else "ok"
                end
      StrengthRow.new(step.id, prev_exit, this_exit, verdict)
    end
  end
end
