# Compile from a repo

Intake only. It ends with a draft `course.md` and hands off to `compile.md`. The repo's history is the code truth. There is no narration, so you write it from the diffs, the PR text and articles.

1. **Make the project.** Create `<root>/<slug>/course/source/` and nothing else. Clone the repo to `course/source/upstream`.
2. **Read the history.** `git -C course/source/upstream log --reverse --format='%h %ad %s' --date=short --shortstat`. Read the README, the first release notes and the tags.
3. **Learner intake and stack.** Run `references/learner-intake.md` now, in at most two `AskUserQuestion` calls. Round 2 carries the stack question and the stand-ins table from `references/stack-wizard.md`. Group and outline only after the learner answered, because the strategy and batch size shape the lessons.
4. **Propose a cutoff.** Pick the commit where the core works, such as a first release tag (`v0.5.0` for Sidekiq). Everything after it is out of scope unless the user asks. Put it in `source.cutoff`.
5. **Group commits.** Group consecutive commits into steps by what they build. Fold noise commits ("Misc", "oops", formatting) into the step they belong to. Group steps into lessons, one feature each.
6. **Find narration.** For each lesson, find the PR or issue text that explains it, and an article per `references/resource-rules.md`. Note them in the lesson's `source:` entry for the writer.
7. **Inventory, then write `course/course.md`** with `status: draft`, the same as `compile-transcript.md` steps 8 and 9. Open `compile.md` at step 1.
