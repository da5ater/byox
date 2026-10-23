#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds a tiny byox course under ROOT: a stdin/stdout "mini-redis" in Ruby with two
# lessons of two steps, a solution repo tagged base, step-01.1 ... step-02.2, real
# tests, verify scripts, a vault with concept pages, and ROOT/byox.yml.
#
#   ruby make_mini_redis.rb ROOT [AGENT_CMD]
require "fileutils"
require "open3"

module MiniRedis
  module_function

  SOLUTION = {
    "01.1" => <<~RUBY,
      $stdout.sync = true
      $stdin.each_line do |line|
        cmd, *args = line.split
        case cmd&.upcase
        when "PING" then puts "PONG"
        end
      end
    RUBY
    "01.2" => <<~RUBY,
      $stdout.sync = true
      $stdin.each_line do |line|
        cmd, *args = line.split
        case cmd&.upcase
        when "PING" then puts "PONG"
        when "ECHO" then puts args.join(" ")
        end
      end
    RUBY
    "02.1" => <<~RUBY,
      $stdout.sync = true
      store = {}
      $stdin.each_line do |line|
        cmd, *args = line.split
        case cmd&.upcase
        when "PING" then puts "PONG"
        when "ECHO" then puts args.join(" ")
        when "SET" then store[args[0]] = args[1]; puts "OK"
        when "GET" then puts store.fetch(args[0], "(nil)")
        end
      end
    RUBY
    "02.2" => <<~RUBY
      $stdout.sync = true
      store = {}
      $stdin.each_line do |line|
        cmd, *args = line.split
        case cmd&.upcase
        when "PING" then puts "PONG"
        when "ECHO" then puts args.join(" ")
        when "SET" then store[args[0]] = args[1]; puts "OK"
        when "GET" then puts store.fetch(args[0], "(nil)")
        when "DEL" then puts(store.delete(args[0]) ? 1 : 0)
        end
      end
    RUBY
  }.freeze

  TESTS = {
    "01.1" => ["ping_test.rb", <<~RUBY],
      require "minitest/autorun"
      require "open3"

      class PingTest < Minitest::Test
        def test_replies_pong_to_every_ping
          n = rand(2..6)
          out, = Open3.capture2e("ruby", "main.rb", stdin_data: "PING\\n" * n)
          assert_equal "PONG\\n" * n, out
        end
      end
    RUBY
    "01.2" => ["echo_test.rb", <<~RUBY],
      require "minitest/autorun"
      require "open3"
      require "securerandom"

      class EchoTest < Minitest::Test
        def test_echoes_the_word_back
          word = "hey-\#{SecureRandom.hex(4)}"
          out, = Open3.capture2e("ruby", "main.rb", stdin_data: "ECHO \#{word}\\nPING\\n")
          assert_equal "\#{word}\\nPONG\\n", out
        end
      end
    RUBY
    "02.1" => ["store_test.rb", <<~RUBY],
      require "minitest/autorun"
      require "open3"
      require "securerandom"

      class StoreTest < Minitest::Test
        def test_get_returns_what_set_stored
          key, val = "k\#{SecureRandom.hex(3)}", "v\#{SecureRandom.hex(3)}"
          out, = Open3.capture2e("ruby", "main.rb", stdin_data: "SET \#{key} \#{val}\\nGET \#{key}\\nGET nope\#{key}\\n")
          assert_equal "OK\\n\#{val}\\n(nil)\\n", out
        end
      end
    RUBY
    "02.2" => ["del_test.rb", <<~RUBY]
      require "minitest/autorun"
      require "open3"
      require "securerandom"

      class DelTest < Minitest::Test
        def test_del_removes_a_key_and_counts_it
          key = "k\#{SecureRandom.hex(3)}"
          out, = Open3.capture2e("ruby", "main.rb", stdin_data: "SET \#{key} 1\\nDEL \#{key}\\nGET \#{key}\\nDEL \#{key}\\n")
          assert_equal "OK\\n1\\n(nil)\\n0\\n", out
        end
      end
    RUBY
  }.freeze

  COURSE_MD = <<~MD
    ---
    byox: 1
    title: Mini Redis
    status: compiled
    source:
      kind: article
      article: course/source/article.md
    stack:
      original: Ruby 3.4
      target: Ruby 3.4
      ported: false
      test: minitest
    services: []
    lessons:
      - id: 01-ping
        title: Talk over stdin
        track: core
        steps:
          - {id: "01.1", title: Reply to PING}
          - {id: "01.2", title: Echo a word back}
      - id: 02-store
        title: Store keys
        track: core
        steps:
          - {id: "02.1", title: SET and GET}
          - {id: "02.2", title: DEL removes a key}
    concepts:
      - {slug: stdin-loop, owner: 01-ping}
      - {slug: key-value-store, owner: 02-store}
    coverage:
      - {feature: PING and ECHO, steps: ["01.1", "01.2"]}
      - {feature: SET, GET and DEL, steps: ["02.1", "02.2"]}
    dropped: []
    ---

    # Mini Redis

    A Redis-like server that reads commands from stdin and writes replies to stdout.
  MD

  LESSONS = {
    "01-ping" => <<~MD,
      ---
      byox: 1
      id: 01-ping
      title: Talk over stdin
      track: core
      goal: |
        Your program reads commands line by line from stdin.
        It answers PING with PONG and ECHO with its argument.
      source:
        sections: ["PING", "ECHO"]
        reconstructed: false
      concepts: [stdin-loop]
      resources:
        - url: https://redis.io/docs/latest/develop/reference/protocol-spec/
          section: "Sending commands to a Redis server"
          why: Shows the request and reply cycle this lesson copies with plain lines.
        - url: https://ruby-doc.org/3.4/IO.html
          section: "Line IO"
          why: Lists the methods that read stdin one line at a time.
      steps:
        - id: "01.1"
          title: Reply to PING
          kind: cli
          verify: sh course/verify/01.1.sh
          generators: []
          generated: []
          instructions: |
            1. Create `main.rb` at the project root.
            2. Read stdin one line at a time until it closes.
            3. Split each line on spaces. The first word is the command.
            4. When the command is PING, print PONG on its own line.
          gotchas: |
            - Output is buffered when stdout is a pipe. Turn on sync or flush after each reply.
            - Commands are case-insensitive. `ping` counts too.
          hints:
            - A loop over the lines of stdin ends by itself when the input closes.
            - "`$stdin` has a method that yields each line. `String#split` with no argument splits on spaces."
            - "Compare the upcased first word with `\\"PING\\"` and `puts` the reply. Set `$stdout.sync`."
        - id: "01.2"
          title: Echo a word back
          kind: cli
          verify: sh course/verify/01.2.sh
          generators: []
          generated: []
          instructions: |
            1. Keep the PING branch.
            2. Add an ECHO command that prints the rest of the line.
          gotchas: |
            - The test sends a word with a random suffix, so a fixed reply fails.
          hints:
            - Everything after the command word is the argument list.
            - Splat assignment can split the first word from the rest.
            - "Join the remaining words with a single space and `puts` them."
      ---

      ## Short read

      Redis is a server you talk to by sending a command and reading one reply. Real Redis
      uses a TCP socket and a framed protocol. Here the transport is stdin and stdout, so
      every line in is one command and every line out is one reply.

      A server like this is a loop: read a request, decide what it means, write an answer,
      repeat until the client goes away. The loop ends when stdin closes.

      ## Task

      - `ruby main.rb` reads commands from stdin, one per line.
      - `PING` prints `PONG`.
      - `ECHO <word>` prints `<word>`.

      ## Tests in plain English

      **01.1.** The check sends `PING` a random number of times, between 2 and 6, and expects
      exactly that many `PONG` lines.

      **01.2.** The check sends `ECHO hey-<random hex>` and then `PING`. It expects the word
      back on one line, then `PONG`.
    MD
    "02-store" => <<~MD
      ---
      byox: 1
      id: 02-store
      title: Store keys
      track: core
      goal: |
        SET stores a value under a key and GET reads it back.
        DEL removes a key and says whether it existed.
      source:
        sections: ["SET and GET", "DEL"]
        reconstructed: false
      concepts: [key-value-store]
      resources:
        - url: https://redis.io/docs/latest/commands/set/
          section: "SET, return information"
          why: The exact reply the real command gives.
        - url: https://ruby-doc.org/3.4/Hash.html
          section: "Methods for fetching"
          why: The hash methods that give a default for a missing key.
      steps:
        - id: "02.1"
          title: SET and GET
          kind: cli
          verify: sh course/verify/02.1.sh
          generators: []
          generated: []
          instructions: |
            1. Keep one store for the life of the process, created before the loop.
            2. SET key value stores the value and prints OK.
            3. GET key prints the value, or `(nil)` when the key was never set.
          gotchas: |
            - Create the store outside the loop. Inside it, every line starts empty.
          hints:
            - A Hash maps keys to values and lives as long as the variable that holds it.
            - Hash has a method that returns a default when the key is missing.
            - "Use `fetch` with `\\"(nil)\\"` as the default for GET."
        - id: "02.2"
          title: DEL removes a key
          kind: cli
          verify: sh course/verify/02.2.sh
          generators: []
          generated: []
          instructions: |
            1. DEL key removes the key.
            2. Print 1 when the key existed and 0 when it did not.
          gotchas: |
            - A second DEL of the same key prints 0.
          hints:
            - Removing from a Hash returns the old value.
            - That return value is nil when nothing was removed.
            - "Turn the return value of `delete` into 1 or 0 with a ternary."
      ---

      ## Short read

      A key-value store is a map that outlives a single request. The server keeps one map in
      memory. Every command reads or changes it. Because the map lives as long as the
      process, a value set by one line is still there for the next.

      ## Task

      - `SET <key> <value>` stores the value and prints `OK`.
      - `GET <key>` prints the value, or `(nil)` for a missing key.
      - `DEL <key>` prints `1` if the key existed, else `0`.

      ## Tests in plain English

      **02.1.** The check sets a random key to a random value, gets it back, then gets a key
      that was never set. It expects `OK`, the value, then `(nil)`.

      **02.2.** The check sets a random key, deletes it, gets it, and deletes it again. It
      expects `OK`, `1`, `(nil)`, `0`.
    MD
  }.freeze

  CONCEPTS = {
    "stdin-loop" => "Read-eval-print loops over stdin",
    "key-value-store" => "In-memory key-value stores",
  }.freeze

  def concept_page(slug, title)
    <<~MD
      ---
      title: #{title}
      origin: mini-redis/#{slug == 'stdin-loop' ? '01-ping' : '02-store'}
      ---

      ## The problem

      Without it, each request starts from nothing.

      ## How it works

      A loop reads one request, answers it, and goes back to reading.

      ## A tiny example

      `ruby -e 'STDIN.each_line { puts _1.upcase }'`

      ## What Ruby does for you

      IO buffers the stream and splits it into lines.

      ## Gotchas

      Pipes buffer output.

      ## Diagrams

      ```mermaid
      flowchart LR
        stdin --> loop --> stdout
      ```
    MD
  end

  def sh!(*cmd, chdir:)
    out, st = Open3.capture2e(*cmd, chdir:)
    raise "#{cmd.join(' ')} failed: #{out}" unless st.success?
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def git(dir, *args) = sh!("git", "-c", "user.name=byox", "-c", "user.email=byox@localhost", *args, chdir: dir)

  # layout :inline keeps the learner's app in the project folder next to course/. :split puts
  # it in work/, so the project folder holds only course/ and work/.
  # projects: :two makes work/ hold two project folders, api (the Ruby program, solution root)
  # and client (a tiny second project, solution subfolder client/).
  def build(root, agent_cmd: "claude -p", layout: :inline, projects: nil)
    root = File.expand_path(root)
    vault = File.join(root, "vault")
    write(File.join(root, "byox.yml"), "vault: #{vault}\nagent_cmd: #{agent_cmd}\n")
    CONCEPTS.each { |slug, title| write(File.join(vault, "Concepts", "#{slug}.md"), concept_page(slug, title)) }
    write(File.join(vault, "learner-profile.md"), "## Knows\n\n- Ruby basics\n")
    write(File.join(vault, "resource-blocklist.md"), "")

    app = File.join(root, "mini-redis")
    c = File.join(app, "course")
    two = projects == :two
    split = layout == :split || two
    course_md = split ? COURSE_MD.sub("byox: 1", "byox: 1\nlayout: split") : COURSE_MD
    course_md = course_md.sub("layout: split\n", "layout: split\nprojects:\n  - {name: api, source: \".\", description: The Ruby program}\n  - {name: client, source: client, description: A tiny second project}\n") if two
    write(File.join(c, "course.md"), course_md)
    write(File.join(c, ".gitignore"), "solution/\nstate.json\n.cache/\n")
    LESSONS.each do |id, text|
      text = text.gsub(/verify: sh course\/verify\/([\d.]+)\.sh/, 'verify: sh "$BYOX_COURSE/verify/\1.sh"') if split
      write(File.join(c, "lessons", "#{id}.md"), text)
    end
    TESTS.each do |step, (name, text)|
      write(File.join(c, "tests", step, name), text)
      script = split ? %(exec ruby "$BYOX_COURSE/tests/#{step}/#{name}") : "exec ruby course/tests/#{step}/#{name}"
      check = two && step == "01.1" ? %(test "$(cat "$BYOX_PROJECT_CLIENT/readme.txt" 2>/dev/null)" = client || { echo "client/readme.txt must say client"; exit 1; }\n) : ""
      write(File.join(c, "verify", "#{step}.sh"), "#!/bin/sh\nset -e\n#{check}#{script}\n")
    end

    sol = File.join(c, "solution")
    FileUtils.mkdir_p(sol)
    git(sol, "init", "-q")
    git(sol, "commit", "-q", "--allow-empty", "-m", "base")
    git(sol, "tag", "base")
    SOLUTION.each do |step, code|
      File.write(File.join(sol, "main.rb"), code)
      if two
        FileUtils.mkdir_p(File.join(sol, "client"))
        File.write(File.join(sol, "client", "readme.txt"), "client\n")
      end
      git(sol, "add", "-A")
      git(sol, "commit", "-q", "-m", step)
      git(sol, "tag", "step-#{step}")
    end

    if two
      %w[api client].each do |name|
        dir = File.join(app, "work", name)
        FileUtils.mkdir_p(dir)
        git(dir, "init", "-q")
        git(dir, "commit", "-q", "--allow-empty", "-m", "Start #{name}")
      end
    elsif split
      work = File.join(app, "work")
      FileUtils.mkdir_p(work)
      git(work, "init", "-q")
      git(work, "commit", "-q", "--allow-empty", "-m", "Start mini-redis")
    else
      git(app, "init", "-q")
      git(app, "add", "-A")
      git(app, "commit", "-q", "-m", "Start mini-redis")
    end
    app
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: ruby make_mini_redis.rb ROOT [AGENT_CMD]" if ARGV.empty?
  puts MiniRedis.build(ARGV[0], agent_cmd: ARGV[1] || "claude -p")
end
