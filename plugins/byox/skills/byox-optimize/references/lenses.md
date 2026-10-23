# Review lenses

Each reviewer takes one lens. Both read the same evidence digest, so a pattern that shows up across stacks, such as Rails, Redis or a frontend course, outranks one inside a single course.

## friction

Where did the learner lose time, guess, or get stuck, and which part of byox made it likely?

- Steps with many attempts, never passed, or passed only after all three hints.
- Lessons skipped, and the notes the learner left: Unclear, Broken, Bad resource, Explain failure.
- Open feedback, and the moments in sessions where the learner corrected the agent, called something clunky or wrong, or repeated an instruction.
- Compare lessons that went well with ones that did not. What did the good ones have: a gotcha found by running the code, a smaller step, a better resource?

Trace each friction point to its cause in byox: a lesson-format rule that is missing, a hint-ladder rule that is too loose, a step size, a resource rule, a UI gap.

## pipeline

Where did compiling, reviewing or running a course go wrong, and what did a person have to fix by hand?

- Lint, strength and audit findings left in a compiled or approved course, such as steps with no tests, lessons with no resources, or a course stuck before `compiled`.
- In sessions: retries, tool errors, commands that failed on this machine, steps the lead agent had to do itself because an agent file or playbook was wrong or silent, agents that disagreed, and work redone.
- Agent budget overshoot, and a step that cost far more tokens than it should.
- Machine and stack surprises: NTFS file modes, the wrong Ruby, a CLI bound to another runtime, a generator that already did the mentor's manual step.

Trace each defect to its cause: a playbook step, an agent file, a script, a reference, or a missing check. Prefer a finding that ends in a lint rule, a script or a template over one that ends in more prose.
