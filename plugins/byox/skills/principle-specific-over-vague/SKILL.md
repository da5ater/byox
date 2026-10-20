---
name: principle-specific-over-vague
description: "Apply when writing any byox lesson text, resource, hint or test description. Exact steps, exact sections of articles, exact expected output."
user-invocable: false
---

# Specific over vague

Write exact steps, exact sections and exact expected output. A learner should never have to guess a name, a path, a command or what done looks like.

**Why:** Vague text moves the work to the learner, who has the least context. "Set up authentication" sends them searching. "Generate the Devise model named `User` and migrate" lets them act.

**Pattern:**

- Steps name the file, the generator and the command.
- Tests in plain English say what the check sends and what it expects, including which values are random.
- Resources point at a heading, a page range or timestamps, never a whole site.
- Gotchas name the concrete edge case: "A second DEL of the same key prints 0", not "watch out for edge cases".

**The test:** Could two learners read this and do different things? If yes, make it more specific.
