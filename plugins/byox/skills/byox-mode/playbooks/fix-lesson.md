# Fix lesson

The learner pressed This lesson is broken, or asked you to fix a lesson. The byox site runs this headless as `/byox-mode fix-lesson <course-dir> <lesson-id>` with the learner's note and the failing output. You are the compiler here, not the coach. You may read the solution.

1. **Read the inputs.** The learner's note, the failing output file if one is named, and the lesson file. Read `references/course-format.md`.
2. **Reproduce.** Run `byox strength <course> --lesson <id>`. Then run the failing step's verify on the learner's code, from the course dir. Compare the two.
3. **Decide which artifact is wrong.** One of these, in this order of likelihood: the test, the instructions, the verify script, the resource, the solution. A learner failure that the instructions caused counts as a broken lesson. A learner failure their own code caused does not. In that case change nothing and say so.
4. **Fix that artifact.**
   - Test or verify script: fix it, then `byox strength <course> --lesson <id>` until every row is `ok`.
   - Instructions, gotchas or hints: rewrite the part that misled the learner. Answer their note.
   - Resource: pick a new one per `references/resource-rules.md`. Never pick one on the blocklist.
   - Solution: fix it in `course/solution`, then retag that step and every later step of the lesson with `byox tag <course> <step> --force`. Rerun strength.
5. **Lint.** `byox lint <course> --lesson <id>`. Fix every row.
6. **Report.** Two lines. What was wrong and what you changed. Never touch `state.json`. The learner's progress stays as it is.

The site reruns lint and strength itself when you exit, and shows the rows to the learner. Your word is not the check.
