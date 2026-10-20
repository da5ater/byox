---
name: principle-test-over-judgment
description: "Apply whenever a byox decision could be checked by a script: lesson format, hints, leaks, links, test strength, a port. Script it or run the existing byox check. The agent judges only what no script can, and the user keeps the final say."
user-invocable: false
---

# Test over judgment

Anything a script can decide, a script decides. You judge only what no script can, and the user keeps the final say.

**Why:** A script gives the same answer every time and a reviewer can rerun it. Your judgment drifts between runs and cannot be rerun. Learners trust a green check because it is a check, not an opinion.

**Pattern:**

- Format, hints, solution leaks, links, the outline and random test values: `byox lint`.
- Whether a step's tests prove the step: `byox strength`.
- Whether a port is faithful: the same tests pass on the ported solution.
- Whether a learner's code works: the step's verify command, exit code 0.
- When you catch yourself checking the same thing by eye twice, add a lint rule instead of a reminder.

**The test:** Is there a `byox` subcommand or a test that would answer this? Run it. If not, and the question will come up again, write one.
