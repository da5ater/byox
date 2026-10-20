# frozen_string_literal: true

# Mechanical intake, so the lead reads a lecture table instead of a 150,000 word file.
module Byox
  Lecture = Data.define(:no, :title, :path, :empty)

  module Source
    module_function

    MARKER = /\A--- (.+) ---\s*\z/
    EMPTY = "[No transcript available]"

    # Splits a transcript on its "--- title ---" lecture markers into OUT/NNN-slug.txt.
    # "=== section ===" lines are dropped, because Udemy exports scramble them.
    def split(transcript, out_dir)
      FileUtils.mkdir_p(out_dir)
      lectures = []
      File.foreach(transcript) do |line|
        if (m = line.match(MARKER))
          lectures << [m[1].strip, +""]
        elsif lectures.any? && !line.start_with?("=== ")
          lectures.last[1] << line
        end
      end
      lectures.each_with_index.map do |(title, text), i|
        no = format("%03d", i + 1)
        path = File.join(out_dir, "#{no}-#{slug(title)}.txt")
        File.write(path, "#{title}\n\n#{text.strip}\n")
        Lecture.new(no:, title:, path:, empty: text.strip.empty? || text.strip.start_with?(EMPTY.delete_suffix("]")))
      end
    end

    def slug(text) = text.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")[0, 60]

    STOP = %w[a an the to for and in of on with by from it is be at as or how use using add part pt gem].freeze

    def words(text)
      text.downcase.scan(/[a-z0-9]+/).map { _1.sub(/s\z/, "") }.reject { _1.size < 2 || STOP.include?(_1) }.uniq
    end

    # Overlap over the shorter title, because commit subjects are much shorter than lecture titles.
    def similarity(a, b)
      wa, wb = words(a), words(b)
      return 0.0 if wa.empty? || wb.empty?

      (wa & wb).size.to_f / [wa.size, wb.size].min
    end

    # Aligns lecture titles with commit subjects, both in order, maximizing the summed
    # similarity of pairs at or above MIN. A global alignment keeps one tempting wrong
    # pair from pushing every later lecture past its commit. A lecture without a transcript
    # can still have a commit, so it matches too, at a discount that hands ties to its spoken twin.
    MIN = 0.5

    def match(lectures_dir, repo, until_ref: "HEAD")
      log = Solution.git(repo, "log", "--reverse", "--format=%H%x09%s", until_ref).lines.map { _1.chomp.split("\t", 2) }
      lectures = Dir[File.join(lectures_dir, "*.txt")].sort.map do |path|
        text = File.read(path)
        title = text.lines.first.to_s.strip
        empty = text.lines.drop(1).join.strip.then { _1.empty? || _1.start_with?(EMPTY.delete_suffix("]")) }
        [File.basename(path)[/\A\d+/], title, empty]
      end
      pairs = align(lectures.map { |_, t, _| t }, log.map(&:last), discount: lectures.map { |_, _, e| e ? 0.99 : 1.0 })
      lectures.each_with_index.map do |(no, title, _), i|
        j = pairs[i]
        j ? [no, title, log[j][0][0, 7], log[j][1], format("%.2f", similarity(title, log[j][1]))] : [no, title, "", "", "0.00"]
      end
    end

    def align(titles, subjects, discount: Array.new(titles.size, 1.0))
      n, m = titles.size, subjects.size
      score = Array.new(n + 1) { Array.new(m + 1, 0.0) }
      (1..n).each do |i|
        (1..m).each do |j|
          s = similarity(titles[i - 1], subjects[j - 1])
          take = s >= MIN ? score[i - 1][j - 1] + s * discount[i - 1] : -1.0
          score[i][j] = [score[i - 1][j], score[i][j - 1], take].max
        end
      end
      pairs = {}
      i, j = n, m
      while i.positive? && j.positive?
        s = similarity(titles[i - 1], subjects[j - 1])
        if s >= MIN && (score[i][j] - (score[i - 1][j - 1] + s * discount[i - 1])).abs < 1e-9
          pairs[i - 1] = j - 1
          i -= 1
          j -= 1
        elsif score[i][j] == score[i - 1][j]
          i -= 1
        else
          j -= 1
        end
      end
      pairs
    end
  end
end
