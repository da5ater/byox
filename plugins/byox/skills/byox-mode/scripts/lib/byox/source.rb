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
        Lecture.new(no:, title:, path:, empty: text.strip.empty? || text.strip == EMPTY)
      end
    end

    def slug(text) = text.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")[0, 60]

    def words(text) = text.downcase.scan(/[a-z0-9]+/).reject { _1.size < 2 }.uniq

    def similarity(a, b)
      wa, wb = words(a), words(b)
      return 0.0 if wa.empty? || wb.empty?

      (wa & wb).size.to_f / (wa | wb).size
    end

    # Matches lecture titles to commit subjects in order. A lecture may only match a
    # commit after the previous match, inside a window, so a repeated title cannot jump
    # backwards. Rows below MIN are left unmatched for the lead to read by hand.
    MIN = 0.3
    WINDOW = 15

    def match(lectures_dir, repo, until_ref: "HEAD")
      log = Solution.git(repo, "log", "--reverse", "--format=%H%x09%s", until_ref).lines.map { _1.chomp.split("\t", 2) }
      pos = 0
      Dir[File.join(lectures_dir, "*.txt")].sort.map do |path|
        title = File.open(path, &:gets).to_s.strip
        no = File.basename(path)[/\A\d+/]
        best = log[pos, WINDOW].to_a.each_with_index.map { |(sha, subj), i| [similarity(title, subj), i, sha, subj] }.max_by(&:first)
        if best && best[0] >= MIN
          pos += best[1] + 1
          [no, title, best[2][0, 7], best[3], format("%.2f", best[0])]
        else
          [no, title, "", "", "0.00"]
        end
      end
    end
  end
end
