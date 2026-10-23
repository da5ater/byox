---
name: byox-optimize
description: "Optimize byox from how it was really used. Reads every course's state, the feedback log, lint and audit results, and this project's Claude Code sessions that used byox. Two read-only reviewers and a synthesizer turn that into learnings, and each accepted one is routed to a concrete edit of a byox skill, playbook, agent, reference or script. Use for /byox-optimize, 'optimize byox', 'reflect on my byox work', 'what should byox do better'."
---

# byox optimize

Mine real use for durable learnings, then route each into an edit of byox. `B` is `scripts/byox` in the `byox-mode` skill next to this one. `R` is the courses root: `--root`, else `BYOX_ROOT`, else `~/byox-courses`. `REPO` is `plugin_repo` in `R/byox.yml`, the byox checkout where edits happen.

Skip when there is nothing to learn from: no courses and no sessions. One-off events are not learnings. A finding needs a systemic cause, or the same trouble in two places: two lessons, two courses, two stacks or two sessions.

## 1. Gather the evidence

`D` is today, `YYYY-MM-DD`.

```bash
mkdir -p R/.byox/optimize/D
B evidence --root R > R/.byox/optimize/D/evidence.md
B transcripts --root R > R/.byox/optimize/D/transcripts.tsv
```

The digest covers every course and stack side by side. The transcript list holds only this project's sessions that used byox. Never read other projects' transcripts. Do not read the evidence or transcripts yourself. The reviewers judge them, and your reading would anchor them.

## 2. Two reviewers, in parallel

One message, two `byox:optimize-reviewer` agents, lenses `friction` and `pipeline`, defined in `references/lenses.md`. Give each paths only: the evidence file, the transcript list, its lens, and `REPO`. Write each reply to `R/.byox/optimize/D/review-<lens>.md`. Their tools are read-only. You apply edits.

## 3. Synthesize

One `byox:optimize-synthesizer` agent, given the paths of both reviews, the evidence and `REPO`. It checks every citation and every target file, merges duplicates, and returns Accepted, Rejected and Backlog. Write it to `R/.byox/optimize/D/synthesis.md`.

The agent budget is these three and no more.

## 4. Structural check

Re-route any Accepted prose edit that a lint rule, a script or a runtime check would enforce more reliably. Writing the rule again in a reference file is the weaker fix. See the **principle-test-over-judgment** skill.

## 5. Approval

Show the full synthesis and wait for approval. The user picks the subset and may redirect a routing. These skills run for every learner and every course, so nothing is applied unasked.

## 6. Apply

Work in `REPO` on a branch `optimize/D`.

- A wording edit of a line or two: do it directly.
- A new section, lint rule or script: test first, run `ruby <plugin>/skills/byox-mode/scripts/test/run.rb`, then commit. One commit per accepted row.
- Each Backlog item: `B feedback add "<one line>" --page "<where>" --root R`. It then appears under Feedback on the site and ships with the feedback agent.

## 7. Summarize

- Applied: file and one line each.
- Backlog filed: one line each.
- Dropped: one line each, with the synthesizer's reason.
- The path of `synthesis.md`.

## Rules

- Never print or repeat a key, token or password that shows up in evidence or a transcript. Say that one exists and where.
- Reviewers and the synthesizer never write files. The parent applies edits.
- Findings cite evidence a reader can open. A claim without a citation is dropped.
