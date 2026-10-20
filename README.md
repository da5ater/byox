# byox

Build Your Own X mode for Claude Code. byox turns a source you already have into a local course in the style of CodeCrafters. The source can be a mentor's transcript, a repo's history, or a Build Your Own X article. You write every line of the code. Each step has its own test that you run with a Verify button on a local site.

## Install

```
/plugin marketplace add <path-to-this-repo-or-github-owner/repo>
/plugin install byox@byox
```

The site and the scripts need Ruby 3.4 and nothing else. There are no gems to install.

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
~/.claude/plugins/cache/byox/byox/0.1.0/skills/byox-mode/scripts/byox site
```

Open `http://127.0.0.1:4917`. Read the lesson, write code in your editor, press Verify. A green step unlocks the next one. A green lesson unlocks the mentor's solution.

## Where things live

- Courses: `<root>/<course>/`, where the root defaults to `/run/media/mohamed/storage/MO/Projects/BuildYourOwnX` and `BYOX_ROOT` overrides it.
- Settings: `<root>/byox.yml`, with `vault:` for the Obsidian folder and `agent_cmd:` for the headless agent command (default `claude -p`).
- Concept pages, progress notes, the learner profile and the resource blocklist: the Obsidian folder.

## Develop

```
ruby plugins/byox/skills/byox-mode/scripts/test/run.rb
ruby plugins/byox/skills/byox-mode/scripts/test/fixtures/make_mini_redis.rb /tmp/byox-demo
plugins/byox/skills/byox-mode/scripts/byox site --root /tmp/byox-demo
```

The fixture builds a two-lesson "mini-redis" course with a real solution repo, tests and concept pages.

## License

MIT, see `LICENSE`. `plugins/byox/skills/byox-teach` is adapted from pstack's teach skill, MIT, see its `LICENSE-pstack`.
