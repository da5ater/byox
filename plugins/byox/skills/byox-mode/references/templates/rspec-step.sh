#!/bin/sh
# Runs one step's RSpec tests inside a Rails project of a byox course.
# Copy to course/support/rspec_step.sh and call it from a step's verify script:
#   sh "$BYOX_COURSE/support/rspec_step.sh" 03.2 api
# With no project it runs in the current folder, the course's first project.
#
# It copies $BYOX_COURSE/tests/<step> into spec/byox/<step> so rails_helper loads,
# runs only those specs under a timeout, and deletes the copy. It refuses to run
# against a test database whose name does not start with byox_, so a learner's
# real databases on the same machine are never touched.
set -e
step="${1:?usage: rspec_step.sh <step> [project]}"
project="$2"
timeout_s="${BYOX_TEST_TIMEOUT:-60}"

if [ -n "$project" ]; then
  var="BYOX_PROJECT_$(printf '%s' "$project" | tr 'a-z-' 'A-Z_')"
  app=$(printenv "$var" || true)
  if [ -z "$app" ]; then
    echo "$var is not set. Run this check from the byox site, or check that $project is in projects: in course.md."
    exit 2
  fi
  cd "$app"
fi

case "${DATABASE_URL:-}" in
  ""|*/byox_*) ;;
  *) echo "DATABASE_URL names a database that does not start with byox_. Unset it. Nothing was run."; exit 1 ;;
esac

if [ ! -f config/database.yml ] || [ ! -f spec/rails_helper.rb ]; then
  echo "$(pwd) has no config/database.yml or spec/rails_helper.rb yet. Generate the app and install rspec-rails first."
  exit 1
fi
test_db=$(ruby -ryaml -rerb -e 'y = YAML.safe_load(ERB.new(File.read("config/database.yml")).result, aliases: true); print y.dig("test", "database")' 2>/dev/null || true)
case "$test_db" in
  byox_*) ;;
  *) echo "config/database.yml names the test database '$test_db'. Name it byox_<project>_test. Nothing was run."; exit 1 ;;
esac

bundle check >/dev/null 2>&1 || bundle install --quiet
export RAILS_ENV=test
ruby bin/rails db:create >/dev/null 2>&1 || true
ruby bin/rails db:schema:load >/dev/null

rm -rf "spec/byox/$step"
mkdir -p spec/byox
cp -R "$BYOX_COURSE/tests/$step" "spec/byox/$step"
status=0
timeout "$timeout_s" bundle exec rspec "spec/byox/$step" --format documentation || status=$?
rm -rf "spec/byox/$step"
rmdir spec/byox 2>/dev/null || true
if [ "$status" = 124 ]; then
  echo "The tests for $step did not finish in ${timeout_s}s. Something waits forever: a lock never released, a thread never joined, or a server never answering."
fi
exit $status
