# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "byox"
require "minitest/autorun"
require "net/http"
require_relative "fixtures/make_mini_redis"

module Fixture
  FAKE_AGENT = <<~RUBY
    require "json"
    File.write(ENV.fetch("FAKE_LOG"), JSON.generate({ "argv" => ARGV, "cwd" => Dir.pwd, "files" => Dir["**/*"].sort,
                                                      "env" => ENV.to_h.slice("BYOX_JOB", "BYOX_LESSON", "BYOX_COURSE") }))
    puts "fake agent ran"
    lesson = ENV["BYOX_LESSON"]
    case ENV["FAKE_MODE"]
    when "break" then File.write(lesson, "not a lesson")
    when "rewrite" then File.write(lesson, File.read(lesson).sub("Redis is a server", "Redis is a database server"))
    when "sleep" then sleep 1.5
    end
  RUBY

  module_function

  def build(agent_cmd: nil)
    root = Dir.mktmpdir("byox-test-")
    fake = File.join(root, "fake_agent.rb")
    File.write(fake, FAKE_AGENT)
    MiniRedis.build(root, agent_cmd: agent_cmd || "ruby #{fake}")
    root
  end

  def course(root) = Byox::Course.load(File.join(root, "mini-redis"))
  def config(root) = Byox::Config.load(root)
  def solution_code(step) = MiniRedis::SOLUTION.fetch(step)

  def edit_lesson(root, id)
    path = File.join(root, "mini-redis", "course", "lessons", "#{id}.md")
    File.write(path, yield(File.read(path)))
  end
end
