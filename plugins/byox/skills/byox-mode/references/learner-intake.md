# Learner intake

Run this first in every compile, before the outline, right after you have read enough of the source to name its parts and its stack. It decides what the course is for, how big each batch is and how it grows. Ask with `AskUserQuestion`, at most two calls, with the recommended option first in every question so the learner can accept in one click. The learner can always pick Other.

## Round 1: the learner

One call, four questions.

1. **Goal in about three months** (multi-select). Offer the outcomes this source can give, such as: take tickets alone in this codebase, draw the whole system, review teammates' code, tell strong stories to a manager or in interviews, build my own version, pass an exam.
2. **How they learn best.** Build it myself from scratch. Trace the real code with guided questions. A mix: build the core, then read the real thing.
3. **Time per week.** 2 to 4 hours, 5 to 8 hours, 10 or more. One lesson takes about one to two hours of learner time.
4. **Breadth or depth first.** The whole system thin first, one area deep first, or "pick for me".

If `<vault>/learner-profile.md` is empty, add a short third call before round 2 with one question: what they already know, as options drawn from the source's stack plus Other.

## Round 2: the course

One call, up to four questions. Build the options from round 1 and the source, never from a fixed list.

1. **Strategy.** Three or four ways to shape the course, each with one line on what it is good for and what it is weak at, tied to the goals from round 1. Recommend a mix first. Typical shapes: follow the source in order; follow one user's journey through the product; replay real tickets or pull requests; reproduce and fix real bugs; a thin pass over everything, then depth.
2. **Stack.** "Same as the source (detected: ...)" first, with the versions you found, then "Port to current versions", per `stack-wizard.md` Batch 1 Q2. Never skip this question, even when the source fixes the stack.
3. **Stand-ins.** The table from `stack-wizard.md` Batch 4 Q3, every external service, private library and sibling service, with the mode you propose for each. Options: "Approve the table", "Fake more", "Use real accounts where possible".
4. **Private source.** "Is this source private or work code?" Yes means `private: true` in `byox.yml` (see `references/obsidian-layout.md`): no feedback pull requests, and optimize findings stay generic.

The rest of the stack wizard runs only for what round 2 and the source did not settle, such as a frontend kit for a port.

## The batch plan

Size the first batch from time per week: about one lesson per week of the learner's time, at least four lessons and at most eight. Name the next two or three batches by theme, so the learner sees how the course grows. Each later batch is added with `playbooks/add-lessons.md`, which starts from `plan.batches`.

## Record it

In `course.md`, before `lessons:`:

```yaml
plan:
  goals: [take tickets alone, draw the whole system]
  hours_per_week: 6
  style: build it myself
  depth: one area deep first
  strategy: one user's journey, steps from real pull requests, one real bug fix per lesson
  batches:
    - {name: core journey, lessons: [01-sign-in, 02-profile, 03-cards]}
    - {name: the employer side, status: planned}
    - {name: money internals, status: planned}
```

In `<vault>/learner-profile.md`, add or update `## Goals`, `## Pace` and `## Style` next to `## Knows` and `## Learning`. Writers and reviewers read it.

`byox lint` requires `plan.goals`, `plan.hours_per_week` and `plan.strategy` once the course is approved.
