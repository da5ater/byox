# Course format

The contract every course file follows. `scripts/lib/byox/format.rb` is its only parser. `byox lint` reports any file that breaks it. Machine-read data goes in YAML front matter. Prose only a human reads goes in the body.

## Folder

```
<root>/<slug>/                 the learner's app, their own git repo
  course/
    course.md                  outline, stack, services, concepts, coverage, dropped
    lessons/NN-slug.md         one file per lesson
    tests/<step>/              the step's tests, any framework
    verify/<step>.sh           the step's verify script
    solution/                  the mentor's code as a git repo: tag "base", then "step-<id>"
    source/                    transcript, lectures/, upstream/, map.tsv, diffs/<step>.diff
    state.json                 written by the site only
    .cache/                    verify logs, written by the site
    .gitignore                 solution/, state.json, .cache/
```

## Ids

- Lesson id `NN-slug`, such as `03-authentication`. The file is `lessons/<id>.md`.
- Step id `NN.k`, such as `03.2`. `NN` is the lesson number.
- The solution tag of a step is always `step-<id>`. The tag before the first step is `base`, an empty commit. Tags are derived, never written in a lesson.

## course.md

```yaml
---
byox: 1
title: Corsego, an online course marketplace
status: draft                     # draft, then approved, then compiled. The site lists only compiled courses.
source:
  kind: transcript+repo           # transcript+repo | transcript | article | repo
  transcript: course/source/transcript.txt
  repo: https://github.com/corsego/corsego
  cutoff: 9f0a3c1
stack:
  original: Rails 6.0, Webpacker, jQuery, Bootstrap 4, HAML
  target: Rails 8.1, importmap, Bootstrap 5, HAML
  ported: true
  test: rspec
services:
  - {name: Stripe, mode: sandbox}  # real | free_tier | sandbox | stub
lessons:                          # list order is unlock order
  - id: 03-authentication
    title: Log in and log out
    track: core                   # core | ops
    lectures: ["017"]
    steps:
      - {id: "03.1", title: Users can sign up and log in, upstream: [5e1c0d2]}
      - {id: "03.2", title: Every page needs a logged-in user, upstream: [5e1c0d2]}
concepts:                         # one owner lesson per new concept page
  - {slug: cookie-sessions, owner: 03-authentication}
coverage:                         # every feature of the final product maps to steps
  - {feature: Pages require login, steps: ["03.2"]}
dropped:
  - {lectures: ["009"], reason: Cloud9 disk space}
---

# Corsego

One paragraph on what the learner builds.
```

The lesson and step ids and titles in `course.md` must match the lesson files exactly. Lint checks it.

## Lesson file

Front matter holds every field a script or the site reads. The body has exactly three H2 sections, in this order: `## Short read`, `## Task`, `## Tests in plain English`.

```yaml
---
byox: 1
id: 03-authentication
title: Log in and log out
track: core
goal: |
  Visitors must sign up or log in before they see any page.
  A navbar shows who is logged in.
source:
  lectures: ["017"]
  upstream: [5e1c0d2]
  reconstructed: false            # true when code truth came from speech
concepts: [cookie-sessions, devise]
resources:                        # exactly 2: primary, then backup
  - url: https://guides.rubyonrails.org/security.html#sessions
    section: "2 Sessions, up to 2.3"
    why: Explains what a session cookie holds and why Rails signs it.
  - url: https://github.com/heartcombo/devise#getting-started
    section: "Getting started, through Controller filters and helpers"
    why: The install steps and helpers this lesson uses.
steps:
  - id: "03.2"
    title: Every page needs a logged-in user
    kind: backend                 # backend | cli | ui | visual | cloud | perf | stub
    verify: sh course/verify/03.2.sh
    generators: []                # commands the learner runs, never types the output of
    generated: []                 # globs of files the generators write
    instructions: |
      1. Make every controller action require a signed-in user, in one place.
      2. Sign out, open `/courses`, and check you land on the log in page.
    hints:
      - Rails runs code before every action of a controller and its subclasses. Which controller do all yours inherit from?
      - Devise gives you a helper that redirects to the log in page when nobody is signed in.
      - "Use `before_action` with Devise's `authenticate_user!`."
---

## Short read

About 2 minutes of reading. Just enough why to do the task, rewritten from the
source with the rambling removed. Never solution code.

## Task

The precise spec, as a short list.

## Tests in plain English

**03.2.** Signed out, the check requests `/courses` and expects a redirect to
`/users/sign_in`. Signed in as a random user, it requests `/courses` and expects 200.
```

### Field rules

- `goal` is two lines. It is shown on the course map.
- Every step has `id`, `title`, `kind`, `verify`, `instructions` and exactly three `hints`. The parser rejects anything else, so the site never sees a step with two hints.
- `verify` is one shell command run from the course dir. The site runs it and goes green on exit code 0. The learner could type it themselves.
- `generators` lists commands like `bin/rails generate devise:install`. `generated` lists globs of the files they write, such as `db/migrate/*_devise_create_users.rb` or `test/**`. The solution view collapses those files, and the leak check ignores them.
- Do not write gotchas. They did not help the learner. A course compiled earlier keeps its `gotchas` field, and the site still shows it.
- `design_url` is optional. On a `visual` step, an https link to the design, such as a Penpot view link. The lesson page shows it as a button.
- `fixed_values` is optional. Set it to one sentence when the expected answer is fixed by the task and cannot be randomized, such as an app's module name or the root route. Lint then skips its random-values check for that step. An empty reason does not count.
- Tests in plain English has one `**<step id>.**` paragraph per step. Say exactly what the check sends and what it expects, including which values are random.

### Hints

A ladder. Hint 1 names the concept. Hint 2 says where to look. Hint 3 nearly gives it away. Hint 3 never contains a full line of the step's solution diff. Lint checks every hand-written line of 12 or more characters.

### No solution in prose

The goal, the three sections, instructions and hints 1 and 2 never contain a line of the solution diff. Lint checks it the same way.

## What the site derives

Never write these. The site computes them on every request.

- The solution tag and the previous step's tag.
- Go deep links, from `concepts:`.
- "Where it shows up" on a concept page, from every lesson that lists the concept.
- The test code fold, from the files in `course/tests/<step>/`.
- The mentor's solution view, from `git diff` between tags, with `generated:` files collapsed. For a ported course, `course/source/diffs/<step>.diff` shows as the original diff.
- Lesson and step status, the current lesson and the weakness log, from `state.json`.
- The shown resource: the first one not on the blocklist.

## Steps unlock in order

Lessons unlock in order. Skip on a lesson unlocks the next one and its solution, and logs the skip. Inside an open lesson, steps unlock in order, because each step's tests assume the one before.

## Quality bar

The auditor scores every lesson on these, 0 to 2 each. Every lesson must score 2 on R5, R6 and R7, and at least 15 of 18 overall, excluding R10. The numbering keeps its gaps so older audit reports stay readable. R10 must be 2.

| # | Dimension | What a 2 looks like |
|---|---|---|
| R1 | Concept, the why | Explains the mechanism, not just the API. |
| R2 | Task precision | Exact inputs and expected outputs. |
| R3 | Tests in plain English | States what the check sends and expects, without reading test code. |
| R5 | Solution withheld | No solution code before the lesson is green or skipped. |
| R6 | Steps without code | An ordered path that still leaves the typing to the learner. |
| R7 | Hint ladder | Three escalating hints, revealed one at a time. |
| R8 | Resource quality | The best human-written material, at the exact section. |
| R9 | Early win | Each step goes green in minutes to an hour. |
| R10 | Source fidelity | Builds what the source built, in its order. |
| R11 | Noise removed | No rambling, no filler. |
