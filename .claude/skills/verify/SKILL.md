---
name: verify
description: "Drive the byox local course site and the byox CLI the way a learner does, and capture proof. Use to verify any change to the byox plugin: the site (lesson page, Verify, hints, solution lock, celebration, agent buttons), the CLI (lint, strength, new, tag, split, match, sync), or a compiled course."
---

# Verify byox

byox has two surfaces. The **site** is a local web app the learner uses every day. The **CLI** is `byox`, which the compile playbooks and the site call. Prove changes on the surface the learner touches. A passing unit test is not proof of a page.

`B` is `plugins/byox/skills/byox-mode/scripts/byox` from the repo root. `RUN` is a scratch dir you create, such as `$(mktemp -d /tmp/byox-verify-XXXX)`. Evidence goes to `.audit/evidence/<date>-<feature>/` at the repo root. That dir survives cleanup.

## Launch

1. Build the fixture course: `ruby plugins/byox/skills/byox-mode/scripts/test/fixtures/make_mini_redis.rb "$RUN"`. It writes `$RUN/byox.yml`, `$RUN/vault/` and the course `$RUN/mini-redis/`, which has 2 lessons of 2 steps, a solution repo tagged `base` and `step-01.1` through `step-02.2`. An optional second argument sets `agent_cmd`. The default is `claude -p`, the real agent.
2. Start the site in the background on a free port: `"$B" site --root "$RUN" --port 4517 > "$RUN/site.log" 2>&1 &` and record `$!` as `PID`.
3. Ready means `curl -sf http://127.0.0.1:4517/api/courses` returns JSON with `"slug":"mini-redis"`. The log line is `byox: 1 course(s) at http://127.0.0.1:4517`.

For a real compiled course, point `--root` at the courses root that holds it. Never start a second site on a root whose site is running. The flock refuses it, and that refusal is correct.

## Doctor

Run it first whenever something looks off. It is read-only.

```bash
curl -sf http://127.0.0.1:4517/api/courses && ss -ltnp | grep 4517 && ruby -v
```

The port must belong to the `PID` you started. `ruby -v` must be 3.4 or newer. No gems are needed.

## Drive

**API (fast, scriptable).** Every button is one route in `ROUTES` in `lib/byox/site.rb`. SSE routes need `curl -sN -X POST`.

| Action | Request |
|---|---|
| Course list | `GET /api/courses` |
| Course map | `GET /api/courses/mini-redis` |
| Lesson | `GET /api/courses/mini-redis/lessons/01-ping` |
| Verify a step | `POST /api/courses/mini-redis/steps/01.1/verify` (SSE, ends with `event: done`) |
| Reveal hint n | `POST /api/courses/mini-redis/steps/01.1/hints/1` |
| Solution, compare | `GET .../lessons/01-ping/solution`, `.../compare` (403 until green or skipped) |
| Explain failure | `POST .../steps/01.1/explain` (SSE, runs `agent_cmd`) |
| Skip | `POST .../lessons/01-ping/skip` |

To act as the learner, write code into `$RUN/mini-redis/main.rb`. The fixture's solution for each step is in `MiniRedis::SOLUTION` in the fixture script.

**Browser (the learner's view).** Open `http://127.0.0.1:4517/` in the browser pane. Hash routes are `#/c/mini-redis`, `#/c/mini-redis/01-ping` and `#/concept/<slug>`. Stable handles: `button[data-verify="01.1"]`, `button[data-explain]`, `button[data-skip]`, `button[data-solution]`, `button[data-compare]`, `button[data-bad]`, `button[data-broken]`, `button[data-unclear]`, `button[data-next]`, `#celebrate`, `#crumbs`. Use `find` with the button label, then click by `ref`.

**CLI.** `"$B" lint "$RUN/mini-redis" --offline` prints zero rows on the clean fixture. `"$B" strength "$RUN/mini-redis"` prints one `ok` row per step.

## Evidence

A proof captures the action and the resulting state.

- API runs: save the full request and response, SSE included, as `.txt`.
- Browser runs: a screenshot before and after the click, plus `get_page_text` of the result.
- Side effects: `cat $RUN/mini-redis/course/state.json` and `cat "$RUN/vault/Courses/mini-redis.md"` after a state change.
- Agent buttons: the streamed agent text and the argv. Set `agent_cmd` to a recording script for argv. Use the real `claude -p` for the real answer.

Exercise the real user path. Never write `state.json` by hand to reach a state. Get there by verifying steps.

## Cleanup

`kill "$PID"`, then confirm `ss -ltn | grep 4517` prints nothing. Remove the scratch dir by its literal absolute path, never through a variable or `dirname`, because Claude Code blocks an `rm -rf` whose target it cannot resolve. Close the browser tab you opened. Never kill by process name. Evidence in `.audit/evidence/` stays.

## Features

See `features/README.md`.
