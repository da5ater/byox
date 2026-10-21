---
name: byox-mode
description: "Build Your Own X mode. Turns a transcript, repo or article into a local CodeCrafters-style course the learner builds line by line, then runs it on a local site. Use for /byox-mode, 'turn this transcript into a course', 'make a course from this repo or article', 'start my byox course', 'open my courses', or 'lesson N is broken'."
---

# byox mode

byox turns a source into a local course. A course is a list of lessons. A lesson is one feature. A step is one commit-sized unit with its own Verify command. The learner writes every line of the code in their own editor and presses Verify on the local site. You build the course. You never write the learner's solution.

The `byox` executable lives at `scripts/byox` next to this file. Call it by its absolute path. It needs only Ruby 3.4, with no gems.

## Rules

Read each principle skill in full before you apply it.

1. **Article over agent.** A human-written article, book chapter or video beats your explanation. See the **principle-article-over-agent** skill.
2. **Test over judgment.** If a script can decide it, a script decides it. Run `byox lint` and `byox strength`. Never hand-check what they check. See the **principle-test-over-judgment** skill.
3. **Specific over vague.** Exact steps, exact sections of articles, exact expected output. See the **principle-specific-over-vague** skill.
4. **Source over imagination.** The course follows the source. Never invent a feature or reorder the story. See the **principle-source-over-imagination** skill.
5. **Facilitate, never teach the answer.** The learner writes every line. Lint blocks solution lines in prose and hints. The coach runs in a directory without the solution.

## Routing

Match the request, then open the playbook. Copy its steps into your todo list verbatim. A step you skip stays in the list with `skip: <reason>`.

| Request | Playbook |
|---|---|
| A transcript, with or without a repo | `playbooks/compile-transcript.md`, then `playbooks/compile.md` |
| A repo URL or path | `playbooks/compile-repo.md`, then `playbooks/compile.md` |
| An article URL or file | `playbooks/compile-article.md`, then `playbooks/compile.md` |
| "start", "open my courses", first run | `playbooks/start-course.md` |
| `fix-lesson <course-dir> <lesson-id>`, or "lesson N is broken" | `playbooks/fix-lesson.md` |
| Feedback on byox itself: "change this", "this is broken", "ship my feedback" | the `feedback` agent. Gather mode talks it through, ship mode runs `playbooks/feedback.md` |
| "Upload my feedback", "upload my changes": the learner changed byox themselves | the `feedback` agent in upload mode, `playbooks/feedback-upload.md` |

Explain failure has no playbook. The site runs the `coach` agent directly.

The learner names the source, the language and the stack in their own words, as in `/byox-mode this transcript ~/Downloads/udemy_transcript_2519558.txt, Rails 8, RSpec`. Ask only for what they left out.

## The contract

Every course file follows `references/course-format.md`. The parser in `scripts/lib/byox/format.rb` is the only reader of course files, so the site, lint and strength all agree. Run `byox lint <course-dir>` after any edit to a course.

Paths:

- Courses root: `byox.yml` sits here. The `--root` flag, else `BYOX_ROOT`, else `~/byox-courses`.
- A course: `<root>/<slug>/`. It is the learner's app and their own git repo. Course files live in `<root>/<slug>/course/`.
- The vault: `vault:` in `byox.yml`, such as a folder in an Obsidian vault. Default `<root>/vault`. See `references/obsidian-layout.md`.

## Agent budget

Two agents per lesson, one `lesson-writer` and then one `lesson-reviewer`, plus one `course-auditor` per course. The reviewer never wrote the lesson it reviews. Nothing else spawns agents, and agents spawn none. Fixes after the audit happen in your own session. At runtime the site runs the `coach`, and the `lesson-writer` or `fix-lesson` headless, one job per course at a time.

## Who writes what

| File | Writer |
|---|---|
| `course/course.md` | You, the lead |
| `course/lessons/<id>.md`, `course/tests/<step>/`, `course/verify/<step>.sh` | That lesson's writer. Later, `fix-lesson` or Unclear. |
| `<vault>/Concepts/<slug>.md` | The writer of the owner lesson named in `course.md`, then that lesson's reviewer. Later, Unclear. |
| `course/solution/` | `byox new` and `byox tag`, called by you or by the writer in port mode |
| `course/state.json`, `<vault>/Courses/<slug>.md`, `<vault>/resource-blocklist.md` | The site only. `byox sync` regenerates the course notes. |
| `course/audit.md` | The course auditor |

## Commands

| Command | Does |
|---|---|
| `byox split TRANSCRIPT OUT_DIR` | Splits a transcript into one file per lecture and prints a lecture table. |
| `byox match LECTURES_DIR REPO [--until REF]` | Matches lecture titles to commit subjects in order. Prints a TSV with a score per row. |
| `byox new COURSE_DIR` | Writes stubs from `course.md` and the solution repo with its `base` tag. Safe to rerun. |
| `byox tag COURSE_DIR STEP [--from REPO SHA] [--force]` | Commits the solution worktree and tags `step-<id>`. `--from` first copies an upstream commit's tree. |
| `byox lint COURSE_DIR [--lesson ID] [--offline]` | Format, hints, leaks, links, outline, tests and concept pages. One TSV row per finding. |
| `byox strength COURSE_DIR [--lesson ID] [--step ID]` | Each step's verify must fail at the previous tag and pass at its own. |
| `byox site [--root DIR] [--port 4917]` | Starts the local site for every compiled course under the root. |
| `byox sync [--root DIR]` | Regenerates every `Courses/<slug>.md` from state. |

Exit codes are 0 for ok, 1 for a failed check, 2 for bad input.
