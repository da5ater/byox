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
| `visual` | The learner builds a page from a design. `references/frontend-design.md` says where the design comes from and how it is handed over. Verify starts the learner's app, screenshots it, and pixel-diffs it against `course/tests/<step>/target.png`, and against `target-phone.png` when there is one. Start from `templates/verify-visual.sh`. The site shows the target next to the step and the red diff after a failed verify. |
| `cloud` | A bash script that runs the real CLI and checks what it says, the way boot.dev does. Each check prints `ok` or `FAIL` with the command, the expected output and what came back. Start from `templates/verify-cloud.sh`. Exempt from the strength check, because it needs an account or an emulator. |
| `perf` | A benchmark script that fails above the lesson's threshold. Print the measured number. |
| `stub` | Tests against the stub or sandbox the user chose for the service in `course.md`. Stripe uses test mode keys. Email uses the framework's test delivery. OAuth uses a mock provider. |

## Cloud and DevOps steps

The learner works against whatever they have. The same script runs unchanged against both, because the AWS CLI reads `AWS_ENDPOINT_URL`.

- **A real account or free tier.** The default. Say in the lesson which services cost money and how to delete them afterward.
- **A local emulator.** [Floci](https://github.com/floci-io/floci) is MIT licensed, needs no account or token, and answers on `http://localhost:4566`. Start it with `docker run -p 4566:4566 floci/floci` and run `export AWS_ENDPOINT_URL=http://localhost:4566`. LocalStack is not an option anymore. Its repository is archived, and its images need an account and an auth token. Docker needs the learner's user in the `docker` group.
- **Other CLIs.** Terraform, kubectl, docker and git work the same way. Check what the CLI prints, with `--output json` and `jq` or `--query` when the output is structured.

Keep a cloud step small enough that its check is one or two CLI calls. Say in the task the exact names the check looks for, such as the bucket `corsego-uploads`, since the script cannot guess them.

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

## Rules every verify script follows

- Call the interpreter explicitly: `ruby bin/rails test ...`, never `bin/rails test ...`. Some drives, such as NTFS, drop the executable bit, and the strength check runs exported copies.
- Exit with a sentence the learner can act on when the app is not there yet, such as "There is no bin/rails in this folder yet. Generate the app here first (step 01.1)."
- Run only the step's own tests, with a path into `course/tests/<step>`. The generated tests in the app's `test/` folder are not the learner's checks.
