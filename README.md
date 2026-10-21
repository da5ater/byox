# byox

Build Your Own X mode for Claude Code. byox turns a source you already have into a local course in the style of CodeCrafters. The source can be a mentor's transcript, a repo's history, or a Build Your Own X article. You write every line of the code. Each step has its own test that you run with a Verify button on a local site.

## Install

```
/plugin marketplace add da5ater/byox
/plugin install byox@byox
```

The site and the scripts need Ruby 3.4 and nothing else. There are no gems to install. Screenshots for feedback pull requests use Playwright, and pull requests use the GitHub CLI, `gh`.

## Make a course

Give the source, the language and the stack in your own words.

```
/byox-mode this transcript ~/Downloads/udemy_transcript_2519558.txt, Rails 8, RSpec
/byox-mode this repo https://github.com/sidekiq/sidekiq, cut off at v0.5.0
/byox-mode this article https://example.com/build-your-own-redis
```

byox proposes an outline, asks about each external service, and waits for your approval. Then it writes one lesson per writer agent, lints every lesson, checks that every step's tests fail before the step and pass after it, reviews the concept pages, and audits the course against its source.

## Take a course

```
/byox-mode start
```

Or run the site yourself:

```
ruby <plugin dir>/skills/byox-mode/scripts/byox site
```

Open `http://127.0.0.1:4917`. Read the lesson, write code in your editor, press Verify. A green step unlocks the next one. A green lesson unlocks the mentor's solution.

## Where things live

- Courses: `<root>/<course>/`. The root is `--root`, else `BYOX_ROOT`, else `~/byox-courses`.
- Settings: `<root>/byox.yml`. Every key is optional: `vault:` for concept pages and progress (default `<root>/vault`, point it into an Obsidian vault if you use one), `agent_cmd:` for the headless agent (default `claude -p`), `upstream:` for where feedback goes (default `da5ater/byox`), and `plugin_repo:` for a local checkout of byox.
- Feedback you have not shipped yet: `<root>/.byox/feedback.jsonl`.

## Feedback and contributing

Something in byox looks wrong, or you want it to work differently? Press **Feedback** on any page of the site and say it in your own words. The page you were on is saved with it. Or tell Claude `/byox-mode I have feedback` and it asks you a few questions to make each item concrete.

When you are ready, press **Send to a pull request**. The `feedback` agent makes each change, takes before and after screenshots of the page, and opens one pull request on `da5ater/byox`, from a fork when you cannot push here. The pull request shows every item with its screenshots, so it can be reviewed without running anything. Nothing is merged without review.

Pull requests by hand are welcome too. Run the tests first.

## Develop

```
ruby plugins/byox/skills/byox-mode/scripts/test/run.rb
ruby plugins/byox/skills/byox-mode/scripts/test/fixtures/make_mini_redis.rb /tmp/byox-demo
plugins/byox/skills/byox-mode/scripts/byox site --root /tmp/byox-demo
```

The fixture builds a two-lesson "mini-redis" course with a real solution repo, tests and concept pages.

## License

MIT, see `LICENSE`. `plugins/byox/skills/byox-teach` is adapted from pstack's teach skill, MIT, see its `LICENSE-pstack`.
