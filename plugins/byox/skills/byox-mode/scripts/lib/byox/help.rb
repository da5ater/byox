# frozen_string_literal: true

# The learner's "I need help with this" flow on a step. An agent interviews them, names the
# gaps, then either finds resources (hard way) or writes a tutorial (easy way). The agents only
# print; this module reads what they printed and saves it, so no agent writes a file.
module Byox
  module Help
    JSON_LINE = /^BYOX_JSON (\{.*\})\s*$/
    MAX_ITEMS = 12

    module_function

    def path(course, step_id) = File.join(course.course_dir, "help", "#{step_id}.json")

    def load(course, step_id)
      file = path(course, step_id)
      File.exist?(file) ? Array(JSON.parse(File.read(file))["items"]) : []
    rescue JSON::ParserError
      []
    end

    def add(course, step_id, items)
      all = load(course, step_id) + items
      FileUtils.mkdir_p(File.dirname(path(course, step_id)))
      File.write(path(course, step_id), JSON.pretty_generate({ "items" => all }))
      all
    end

    # The last BYOX_JSON line of the agent's output, or nil.
    def last_json(output)
      line = output.lines.reverse.find { _1.match?(JSON_LINE) }
      line && JSON.parse(JSON_LINE.match(line)[1])
    rescue JSON::ParserError
      nil
    end

    # What the agent is told about the conversation so far. gaps is the diagnosis, once there is one.
    def transcript(messages, gaps)
      lines = Array(messages).filter_map do |m|
        text = m["text"].to_s.strip
        "#{m['role'] == 'coach' ? 'Coach' : 'Learner'}: #{text}" unless text.empty?
      end
      lines << "Diagnosis:\n#{Array(gaps).map { |g| "- #{g['id']}: #{g['gap']}. #{g['detail']}" }.join("\n")}" if Array(gaps).any?
      lines.join("\n")
    end

    # Keeps only well-formed web resources that are not blocklisted.
    def clean_resources(items, blocklist)
      Array(items).first(MAX_ITEMS).filter_map do |i|
        url, title, why = %w[url title why].map { i[_1].to_s.strip }
        next if url.empty? || title.empty? || why.empty? || !url.match?(%r{\Ahttps?://}) || blocklist.include?(url)

        kind = i["kind"] == "tutorial" ? "tutorial" : "gap"
        { "kind" => kind, "way" => "hard", "gap" => (kind == "gap" ? i["gap"].to_s.strip : nil),
          "title" => title, "url" => url, "section" => i["section"].to_s.strip, "why" => why }
      end
    end

    # The easy way prints "TITLE: ..." and the tutorial after it. Anything before the title line is dropped.
    def tutorial(output)
      from = output.index(/^TITLE: /) or return nil
      title, body = output[from..].strip.split("\n", 2)
      return nil unless body.to_s.strip.length > 200

      { "kind" => "tutorial", "way" => "easy", "title" => title.delete_prefix("TITLE: ").strip, "body" => body.strip }
    end
  end
end
