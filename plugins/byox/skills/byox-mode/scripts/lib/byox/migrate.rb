# frozen_string_literal: true

module Byox
  # Turns an inline course, where the learner's app is the project folder with course/
  # inside it, into a split one: course/ for the agent, work/ for the learner. With
  # projects: it also groups the work into named project folders such as api and frontend,
  # moving a project that lived inside the app out to its own folder. Only verify commands
  # and scripts are rewritten, so the tests keep passing. Test files are never touched. A
  # path inside one is reported for a person to look at.
  module Migrate
    # course/..., ./course/... and ../course/... from a subfolder the script cd'd into.
    COURSE_PATH = %r{(?<![\w/.-])(?:\.{1,2}/)*course/(tests|verify|support|design|\.cache|source)/([^\s"']*)}
    Plan = Data.define(:moves, :rewrites, :warnings)

    module_function

    def plan(course, projects: nil)
      names = validate_projects!(course, projects)
      raise ArgumentError, "#{course.dir} is already split" if names.nil? && course.layout == "split"

      work = course.work_dir
      raise ArgumentError, "work already exists: #{work}. Move it away first." if names.nil? && File.exist?(work)

      split = course.layout == "split"
      children = split ? Dir.children(work) : Dir.children(course.dir) - ["course"]
      moves = children.sort.map do |c|
        from = split ? "work/#{c}" : c
        to = names.nil? ? "work/#{c}" : (names.drop(1).include?(c) ? "work/#{c}" : "work/#{names.first}/#{c}")
        [from, to]
      end
      raise ArgumentError, "work/#{names.first} already exists. Choose another name for the main project." if names && children.include?(names.first)

      rewrites = {}
      add = lambda { |path, text| rewrites[path] = text if text != File.read(path) }
      cmd = File.join(course.course_dir, "course.md")
      add.call(cmd, declare_projects(declare_split(File.read(cmd)), names))
      Dir[File.join(course.course_dir, "lessons", "*.md")].sort.each { |p| add.call(p, rewrite_verify_lines(File.read(p))) }
      Dir[File.join(course.course_dir, "verify", "*")].sort.select { File.file?(_1) }.each do |p|
        add.call(p, rewrite_projects(rewrite_text(File.read(p)), names))
      end
      Plan.new(moves:, rewrites:, warnings: warnings(course, rewrites))
    end

    NAME = /\A[a-z][a-z0-9_-]*\z/

    def validate_projects!(course, projects)
      return nil if projects.nil?

      raise ArgumentError, "#{course.slug} already declares projects" if course.multi?
      raise ArgumentError, "give at least two project names, such as api,frontend" if projects.size < 2
      bad = projects.reject { _1.match?(NAME) }
      raise ArgumentError, "project names must be lowercase letters, digits, - or _: #{bad.join(', ')}" unless bad.empty?
      raise ArgumentError, "duplicate project name in #{projects.join(',')}" unless projects.uniq.size == projects.size

      projects
    end

    def declare_split(text)
      return text if text.match?(/^layout: split$/)

      text.match?(/^byox: 1\n/) ? text.sub(/^byox: 1\n/, "byox: 1\nlayout: split\n") : text.sub(/\A---\n/, "---\nlayout: split\n")
    end

    # The first project is the app the learner already has, so its solution source is the repo
    # root. The others lived inside it, in a folder of the same name.
    def declare_projects(text, names)
      return text unless names

      lines = names.each_with_index.map { |n, i| %(  - {name: #{n}, source: #{i.zero? ? '"."' : n}}\n) }.join
      text.sub(/^layout: split\n/) { "layout: split\nprojects:\n#{lines}" }
    end

    # Paths of the other projects, and cd into them, become their variables. The main
    # project is where verify already runs, so its paths are left as they are.
    def rewrite_projects(text, names)
      return text unless names

      names.drop(1).reduce(text) do |t, name|
        var = "BYOX_PROJECT_#{name.upcase.gsub(/[^A-Z0-9]/, '_')}"
        t = t.gsub(/(?<![\w\/.-])cd\s+#{Regexp.escape(name)}(?=[\s;&|)]|\z)/) { %(cd "$#{var}") }
        t.lines.map { |l| rewrite_project_line(l, name, var) }.join
      end
    end

    def rewrite_project_line(line, name, var)
      line.gsub(%r{(?<![\w/.-])(?:\./)?#{Regexp.escape(name)}/([^\s"']*)}) do
        m = Regexp.last_match
        before = m.pre_match
        rest = m[1]
        if before.count("'").odd? && before.count('"').even? then m[0]
        elsif before.count('"').odd? then "$#{var}/#{rest}"
        elsif rest.match?(/[*?\[]/) then %("$#{var}"/#{rest})
        else %("$#{var}/#{rest}")
        end
      end
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

    def run(dir, dry_run: false, projects: nil, out: $stdout)
      course = Course.load(dir)
      plan = plan(course, projects:)
      lines = plan.moves.map { |from, to| from == to ? "keep #{from}" : "move #{from} -> #{to}" } +
              plan.rewrites.keys.map { "rewrite #{_1.delete_prefix("#{course.dir}/")}" } + plan.warnings
      lines.each { out.puts _1 }
      return plan if dry_run

      apply(course, plan)
      out.puts "Done. The learner's files are in #{course.work_dir}. Undo log: course/.cache/migrate.log"
      plan
    end

    def apply(course, plan)
      FileUtils.mkdir_p(course.work_dir)
      moved = []
      begin
        plan.moves.each do |from, to|
          next if from == to

          src = File.join(course.dir, from)
          dest = File.join(course.dir, to)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.mv(src, dest)
          moved << [from, to]
        end
      rescue StandardError
        moved.reverse_each { |from, to| FileUtils.mv(File.join(course.dir, to), File.join(course.dir, from)) }
        raise
      end
      backup = File.join(course.course_dir, ".cache", "migrate-backup")
      log = ["Moved:", *moved.map { |from, to| "  #{from} -> #{to}" }, "Rewritten, originals saved in course/.cache/migrate-backup/:"]
      plan.rewrites.each do |path, text|
        rel = path.delete_prefix("#{course.dir}/")
        FileUtils.mkdir_p(File.dirname(File.join(backup, rel)))
        FileUtils.cp(path, File.join(backup, rel)) unless File.exist?(File.join(backup, rel))
        File.write(path, text)
        log << "  #{rel}"
      end
      File.write(File.join(course.course_dir, ".cache", "migrate.log"), log.join("\n") + "\n")
    end
  end
end
