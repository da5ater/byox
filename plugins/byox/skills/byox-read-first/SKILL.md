---
name: byox-read-first
description: Picks the one or two things a learner should read before a byox step, at the exact section, and says why this step needs them. Use before writing a step's read_first field or a lesson's resources, and when a learner says the resources do not match the step. Adapted from learn-before-task by zezo-mohamed22 (MIT).
---

# Read first

A lesson's two resources teach the idea. A step's `read_first` teaches the thing the learner is about to do. Before the agent writes the task, it decides what the learner must understand to do it, and sends them to the exact page.

Adapted from the `learn-before-task` skill (https://github.com/zezo-mohamed22/learn-before-task, MIT), which gives a short "learn first" brief before any ticket: the problem, the few concepts it depends on and why, trusted resources only, and a small plan. byox uses its method per step.

## Method

1. **Read the step.** What exact thing does the learner do? Name the tool, the file and the result.
2. **Find the gap.** What does a learner who finished the previous step still not know that this step needs? Skip what they already know.
3. **Pick one or two concepts**, not every topic the step touches. Prefer the one that would stop them dead if they did not know it: "how Vite reads the Tailwind plugin", "what a Penpot board is and how to read its spacing".
4. **Tie each to this step.** One sentence in `why`: where in this step it matters. A reading with no link to the step does not belong.
5. **Choose the source.** Official docs first, then well known books and respected engineering blogs. Open the page and read the section before choosing it. Never invent a title, author or link. When unsure, name the official docs site instead. `resource-rules.md` still applies: the blocklist, one primary, human written first.
6. **Point at the exact section**, not the site. `section` is the heading on that page.
7. **Add the design when there is one.** A step with a `design_url` also reads its design first: say which board and which numbers to read (spacing, color, text size) in the `why`.

## The field

```yaml
read_first:
  - url: https://tailwindcss.com/docs/installation/using-vite
    section: "Install Tailwind CSS with Vite"
    why: Step 02.1 adds the Tailwind plugin to your Vite config. This page shows the two lines.
  - url: https://ui.shadcn.com/docs/installation/vite
    section: "Run the CLI"
    why: Step 02.3 runs this command. Read what each prompt means before you answer it.
```

At most two entries. Each has `url`, `section` and `why`. Lint checks the links resolve and are not on the blocklist.

## Self-check questions

When the step teaches an idea, end the Short read or the first item with one "predict" question the learner answers in their head: "What do you think the browser will show if the API is on another port?" Do not give the answer.

## Never

- More than two entries. A list of ten links is a wall.
- A link the writer did not open.
- A reading that repeats the step's own instructions.
