# frozen_string_literal: true

# Views of the mentor's solution repo at course/solution: an empty commit tagged
# "base", then one tag "step-<id>" per step. Reads never touch its index or worktree,
# so strength runs and the site can read it at the same time.
module Byox
  FileDiff = Data.define(:path, :generated, :patch)

  module Solution
    module_function

    MIN_LINE = 12
    GIT_ID = ["-c", "user.name=byox", "-c", "user.email=byox@localhost"].freeze

    def git(dir, *args)
      out, err, st = Open3.capture3("git", "-C", dir, *args)
      raise "git #{args.join(' ')}: #{err.strip}" unless st.success?

      out
    end

    def tag?(course, tag)
      system("git", "-C", course.solution_dir, "rev-parse", "-q", "--verify", "refs/tags/#{tag}", out: File::NULL, err: File::NULL)
    end

    def export(course, tag, dest)
      FileUtils.mkdir_p(dest)
      ok = system("git -C #{course.solution_dir.shellescape} archive #{tag.shellescape} | tar -x -C #{dest.shellescape}")
      raise "cannot export #{tag}" unless ok
    end

    def split_patch(patch, globs)
      patch.split(/^(?=diff --git )/).filter_map do |chunk|
        path = chunk[%r{\Adiff --git a/\S+ b/(\S+)}, 1] or next
        FileDiff.new(path:, generated: Format.generated?(path, globs), patch: chunk)
      end
    end

    def step_diff(course, step)
      patch = git(course.solution_dir, "diff", "--no-color", course.previous_tag(step.id), step.tag)
      split_patch(patch, step.generated)
    end

    # Hand-written lines the step added. Generated files and short lines like `end` are ignored.
    def added_lines(course, step)
      step_diff(course, step).reject(&:generated).flat_map do |d|
        d.patch.lines.filter_map { |l| l[1..].strip if l.start_with?("+") && !l.start_with?("+++") }
      end.select { _1.length >= MIN_LINE }.uniq
    end

    # The learner's files against the solution at the lesson's last tag, for the
    # hand-written paths the lesson's solution changed.
    def compare(course, lesson)
      first, last = lesson.steps.first, lesson.steps.last
      globs = lesson.steps.flat_map(&:generated)
      changed = split_patch(git(course.solution_dir, "diff", "--no-color", course.previous_tag(first.id), last.tag), globs)
      Dir.mktmpdir("byox-compare-") do |tmp|
        export(course, last.tag, tmp)
        changed.reject(&:generated).map do |d|
          mine = File.join(course.dir, d.path)
          theirs = File.join(tmp, d.path)
          out, = Open3.capture2("git", "diff", "--no-index", "--no-color", "--no-prefix",
                                File.exist?(mine) ? mine : File::NULL, File.exist?(theirs) ? theirs : File::NULL)
          FileDiff.new(path: d.path, generated: false,
                       patch: relabel(relabel(out, mine, "yours/#{d.path}"), theirs, "solution/#{d.path}"))
        end
      end
    end

    # git prints --no-index paths without their leading slash.
    def relabel(patch, path, label) = patch.gsub(%r{/?#{Regexp.escape(path.delete_prefix('/'))}}, label)

    # Commits the solution worktree and tags it step-<id>. With `from:`, the worktree
    # is first replaced by the tree of an upstream commit.
    def tag(course, step_id, from: nil, force: false)
      dir = course.solution_dir
      if from
        repo, sha = from
        git(dir, "rm", "-rq", "--ignore-unmatch", ".")
        ok = system("git -C #{File.expand_path(repo).shellescape} archive #{sha.shellescape} | tar -x -C #{dir.shellescape}")
        raise "cannot read #{sha} from #{repo}" unless ok
      end
      git(dir, "add", "-A")
      mark_scripts_executable(dir)
      git(dir, *GIT_ID, "commit", "-q", "--allow-empty", "-m", step_id)
      git(dir, "tag", *(force ? ["-f"] : []), "step-#{step_id}")
    end

    # Drives like NTFS make git ignore file modes, so bin/rails lands as 100644 and an
    # exported tree cannot run it. A shebang is the portable signal that a file is a script.
    def mark_scripts_executable(dir)
      scripts = git(dir, "ls-files", "-s").lines.filter_map do |line|
        mode, _, _, path = line.chomp.split(/\s+/, 4)
        path if mode == "100644" && File.open(File.join(dir, path), "rb") { _1.read(2) } == "#!"
      end
      scripts.each_slice(200) { git(dir, "update-index", "--chmod=+x", "--", *_1) }
    end

    def init(course)
      dir = course.solution_dir
      return if File.directory?(File.join(dir, ".git"))

      FileUtils.mkdir_p(dir)
      git(dir, "init", "-q")
      git(dir, *GIT_ID, "commit", "-q", "--allow-empty", "-m", "base")
      git(dir, "tag", "base")
    end
  end
end
