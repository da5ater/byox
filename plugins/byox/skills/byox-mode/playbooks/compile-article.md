# Compile from an article

Intake only. It ends with a draft `course.md` and hands off to `compile.md`. Build Your Own X articles are the typical source.

1. **Make the project.** Create `<root>/<slug>/course/source/` and nothing else. `byox new` makes `work/` later.
2. **Save the article.** Save it as Markdown to `course/source/article.md`. Keep its headings and every code listing.
3. **Find the code.** If the article links a repo, clone it to `course/source/upstream` and treat it as code truth, the same as `compile-repo.md`. Otherwise the article's listings are the code truth.
4. **Learner intake and stack.** Run `references/learner-intake.md` now, in at most two `AskUserQuestion` calls. Round 2 carries the stack question and the stand-ins table from `references/stack-wizard.md`. Group and outline only after the learner answered, because the strategy and batch size shape the lessons.
5. **Group into lessons.** Each heading that builds something is a lesson candidate. Each code listing is a step candidate. Merge listings that make sense only together.
6. **Resources.** The article is the primary resource for its own lessons, pointed at the exact heading. Pick a backup per `references/resource-rules.md`.
7. **Inventory, then write `course/course.md`** with `status: draft`, the same as `compile-transcript.md` steps 8 and 9. Open `compile.md` at step 1.
