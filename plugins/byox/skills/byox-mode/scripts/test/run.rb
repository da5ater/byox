# frozen_string_literal: true

# Runs every byox test: ruby plugins/byox/skills/byox-mode/scripts/test/run.rb
Dir[File.join(__dir__, "*_test.rb")].sort.each { require _1 }
