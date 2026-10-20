# Verify recipes

Every step's `verify` field names one shell command, usually `sh course/verify/<step>.sh`. It runs from the course dir, in the learner's repo or in a temp export of a solution tag during `byox strength`. Exit code 0 is green.

## Rules for every recipe

- **Idempotent.** Running it twice gives the same result. Install only when missing (`bundle check || bundle install`). Reset the test database (`bin/rails db:test:prepare`).
- **Fast.** A verify should finish in seconds. Run only the step's own tests.
- **Visible.** All tests live in `course/tests/<step>/`. There are no hidden tests.
- **Random values.** Anything a learner could hardcode comes from `SecureRandom`, `rand`, Faker or `$RANDOM`. Lint fails a test dir with no random source.
- **Strong.** The tests must fail on the solution at the previous tag and pass at this step's tag. `byox strength` checks it. Only `kind: cloud` steps are exempt.
- **Readable failure.** The first failing line says what was expected and what came back.

## By kind

| kind | Recipe |
|---|---|
| `backend` | Request or model tests in the course's framework. Rails with RSpec: `bundle exec rspec course/tests/<step>`. Add a support file under `course/support/` for shared helpers such as Devise sign in. |
| `cli` | Feed input on stdin and compare stdout, or run a client script against the learner's server. Keep `N.in` and `N.out` files in the test dir when the output is fixed, and generate input in the test when it must be random. |
| `ui` | Browser tests that click, fill and read the page. Rails system tests or Playwright. Assert on visible text and roles, not CSS classes. |
| `visual` | Pixel diff with a tolerance against `course/tests/<step>/target.png`. The target comes from the mentor's code at that step, such as a Storybook story or a screenshot of the running solution. If the diff fails, the agent lists the visible differences and the learner decides. |
| `cloud` | A bash script that calls the real CLI and checks its answer, such as `aws s3api head-object`. Exempt from the strength check. |
| `perf` | A benchmark script that fails above the lesson's threshold. Print the measured number. |
| `stub` | Tests against the stub or sandbox the user chose for the service in `course.md`. Stripe uses test mode keys. Email uses the framework's test delivery. OAuth uses a mock provider. |

## Example: Rails request spec

```sh
#!/bin/sh
set -e
bundle check >/dev/null 2>&1 || bundle install --quiet
bin/rails db:test:prepare >/dev/null
exec bundle exec rspec course/tests/03.2 --require ./course/support/devise_helpers.rb
```

## Example: stdin and stdout

```sh
#!/bin/sh
set -e
exec ruby course/tests/01.2/echo_test.rb
```

The test runs `ruby main.rb` with a random word on stdin and compares the reply.
