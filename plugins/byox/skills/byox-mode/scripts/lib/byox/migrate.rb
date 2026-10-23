# frozen_string_literal: true

module Byox
  # Turns an inline course, where the learner's app is the project folder with course/
  # inside it, into a split one: course/ for the agent, work/ for the learner. Only verify
  # commands and scripts are rewritten, so the tests keep passing. Test files are never
  # touched. A path inside one is reported for a person to look at.
  module Migrate
    # course/..., ./course/... and ../course/... from a subfolder the script cd'd into.
    COURSE_PATH = %r{(?<![\w/.-])(?:\.{1,2}/)*course/(tests|verify|support|design|\.cache|source)/([^\s"']*)}
    Plan = Data.define(:moves, :rewrites, :warnings)

    module_function

    def plan(course)
      raise ArgumentError, "#{course.dir} is already split" if course.layout == "split"

      work = File.join(course.dir, "work")
      raise ArgumentError, "work already exists: #{work}. Move it away first." if File.exist?(work)

      rewrites = {}
      add = lambda { |path, text| rewrites[path] = text if text != File.read(path) }
      add.call(File.join(course.course_dir, "course.md"), declare_split(File.read(File.join(course.course_dir, "course.md"))))
      Dir[File.join(course.course_dir, "lessons", "*.md")].sort.each { |p| add.call(p, rewrite_verify_lines(File.read(p))) }
      Dir[File.join(course.course_dir, "verify", "*")].sort.select { File.file?(_1) }.each { |p| add.call(p, rewrite_text(File.read(p))) }
      Plan.new(moves: (Dir.children(course.dir) - ["course"]).sort, rewrites:, warnings: warnings(course, rewrites))
    end

    def declare_split(text)
      text.match?(/^byox: 1\n/) ? text.sub(/^byox: 1\n/, "byox: 1\nlayout: split\n") : text.sub(/\A---\n/, "---\nlayout: split\n")
    end

    def rewrite_verify_lines(text)
      text.lines.map { |l| l.match?(/\A\s*verify:/) ? rewrite_line(l) : l }.join
    end

    def rewrite_text(text) = text.lines.map { rewrite_line(_1) }.join

    # A path inside double quotes only needs the variable. A bare path gets quotes, so a
    # project folder with a space in its name still works, except that a wildcard must stay
    # outside the quotes or it stops expanding. A path in single quotes would not expand the
    # variable, so it is left alone and reported.
    def rewrite_line(line)
      line.gsub(COURSE_PATH) do
        m = Regexp.last_match
        before = m.pre_match
        dir, rest = m[1], m[2]
        if before.count("'").odd? && before.count('"').even? then m[0]
        elsif before.count('"').odd? then "$BYOX_COURSE/#{dir}/#{rest}"
        elsif rest.match?(/[*?\[]/) then %("$BYOX_COURSE"/#{dir}/#{rest})
        else %("$BYOX_COURSE/#{dir}/#{rest}")
        end
      end
    end

    def warnings(course, rewrites)
      files = Dir[File.join(course.course_dir, "{tests,support}", "**", "*")].select { File.file?(_1) && !Checks::BINARY.include?(File.extname(_1).downcase) }
      hits = files.flat_map do |f|
        File.readlines(f).each_with_index.filter_map { |l, i| "needs a manual look: #{f.delete_prefix("#{course.dir}/")}:#{i + 1}" if l.match?(COURSE_PATH) }
      end
      single = rewrites.keys.flat_map { |f| rewrites[f].lines.each_with_index.filter_map { |l, i| "needs a manual look: #{f.delete_prefix("#{course.dir}/")}:#{i + 1} (path in single quotes)" if l.match?(/'[^']*course\/(tests|verify|support)\//) } }
      hits + single
    end

    def run(dir, dry_run: false, out: $stdout)
      course = Course.load(dir)
      plan = plan(course)
      lines = plan.moves.map { "move #{_1} -> work/#{_1}" } +
              plan.rewrites.keys.map { "rewrite #{_1.delete_prefix("#{course.dir}/")}" } + plan.warnings
      lines.each { out.puts _1 }
      return plan if dry_run

      apply(course, plan)
      out.puts "Done. The learner's files are in #{File.join(course.dir, 'work')}. Undo log: course/.cache/migrate.log"
      plan
    end

    def apply(course, plan)
      work = File.join(course.dir, "work")
      FileUtils.mkdir_p(work)
      moved = []
      begin
        plan.moves.each do |name|
          FileUtils.mv(File.join(course.dir, name), File.join(work, name))
          moved << name
        end
      rescue StandardError
        moved.reverse_each { FileUtils.mv(File.join(work, _1), File.join(course.dir, _1)) }
        Dir.rmdir(work)
        raise
      end
      backup = File.join(course.course_dir, ".cache", "migrate-backup")
      log = ["Moved into work/:", *plan.moves.map { "  #{_1}" }, "Rewritten, originals saved in course/.cache/migrate-backup/:"]
      plan.rewrites.each do |path, text|
        rel = path.delete_prefix("#{course.dir}/")
        FileUtils.mkdir_p(File.dirname(File.join(backup, rel)))
        FileUtils.cp(path, File.join(backup, rel))
        File.write(path, text)
        log << "  #{rel}"
      end
      File.write(File.join(course.course_dir, ".cache", "migrate.log"), log.join("\n") + "\n")
    end
  end
end
