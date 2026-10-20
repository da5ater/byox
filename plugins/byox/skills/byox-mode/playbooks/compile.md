# Compile

Shared by every source. Start here after an intake playbook wrote a draft `course/course.md`. `B` below is the absolute path of `scripts/byox` next to `SKILL.md`. `C` is the course dir.

1. **Questions.** Ask only what the user left out, one short question each.
   - The stack, when the source fixes it. Keep it or port it. Default: port to the current version, such as Rails 8 instead of Rails 6 with Webpacker. Read `references/porting.md` before you answer for them.
   - The test framework. Default: the source's.
   - Per external service: a real account, a free tier or a stub. Stripe, AWS, OAuth and email are the usual ones.
   Write the answers into `stack:` and `services:` in `course.md`.
2. **Approval.** Show the outline: lessons and steps, the coverage table, the ops track and the dropped list with reasons. Revise until the user says yes. Then set `status: approved`.
3. **Scaffold.** `B new C`. It writes lesson stubs, test dirs, verify stubs, `course/.gitignore`, and `course/solution` with an empty commit tagged `base`. List the concepts in `course.md` whose page does not exist yet in `<vault>/Concepts/`. That list is the reviewer's batch in step 8.
4. **Diffs.** With an upstream repo, write each step's mentor diff for its writer: `git -C C/course/source/upstream diff <first-sha>^ <last-sha> > C/course/source/diffs/<step>.diff`. Without a repo, skip.
5. **Solution repo, when not ported.** For each step in order, `B tag C <step> --from C/course/source/upstream <last-sha-of-step>`. Ported courses skip this, because the writers build it in step 6.
6. **Writers.** Spawn one `lesson-writer` per lesson. Not ported: all at once. Ported: in lesson order, each after the previous one returns, because lesson N's port starts from lesson N-1's last tag. Give each writer paths only:
   - the course dir and its lesson id,
   - its lecture files or article section, and its step diffs,
   - `references/course-format.md`, `verify-recipes.md`, `resource-rules.md`, `concept-rubric.md`, and `porting.md` when ported,
   - `<vault>/learner-profile.md` and `<vault>/resource-blocklist.md`,
   - the absolute path of `B`,
   - in port mode, the base tag and the target stack.
7. **Lint and strength.** `B lint C` and `B strength C`. Fix every row in this session. Do not spawn the writer again.
8. **Concept review.** Spawn one `concept-reviewer` with the batch from step 3, `references/concept-rubric.md`, `references/resource-rules.md`, the learner profile and the blocklist. Then rerun `B lint C`.
9. **Audit.** Spawn one `course-auditor` with the course dir and `B`. It writes `course/audit.md`. Fix each finding in this session, then rerun step 7.
10. **Done.** Set `status: compiled`. Run `B sync`. Tell the user to start the site with `B site`, or run `start-course.md`.
