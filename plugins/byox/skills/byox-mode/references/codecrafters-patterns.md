# What CodeCrafters stages do

Read from the learner's saved stages of "Build your own Shell" (ten stages: invalid commands, a REPL, `exit`, `echo`, `type`, locating executables, running a program, `pwd`, `cd`, single quotes). The patterns below are what makes the stages easy to start. byox copies the ideas, never the text.

## One stage, in order

1. **One plain sentence.** "In this stage, you'll implement the `echo` builtin." The whole job in one line, with a difficulty tag (Easy, Medium).
2. **The concept, small.** A short heading, two or three sentences, then a worked example as a real terminal session: the command the user types and what comes back. Tables for rules with several cases (command, expected output, why).
3. **What gets checked.** The exact session the checker will run, with inputs and outputs. The learner never wonders what "done" means.
4. **Notes.** Language traps in one or two bullets ("your print function may already add a newline").
5. **Hints as questions.** "How do I identify the echo command?" then a tiny code snippet in the learner's language and one line on why it works. Hints grow from naming the idea to showing the shape. They never show the finished program.
6. **The diff.** After the stage passes, the mentor's change appears as a small diff of a few lines.

## The path between stages

- Each stage adds one behavior to the program that already runs. `exit`, then `echo`, then `type`, never all at once.
- Later stages reuse earlier code: running a program reuses the lookup written for `type`. The stage says so in one sentence.
- A stage is a few lines of change. If it would be more, it is two stages.
- Hard stages arrive late (quoting comes after the basics), and carry the "Medium" tag.

## What byox takes from this

| CodeCrafters | byox |
|---|---|
| One plain sentence | The first line of the Short read, "What you're building" |
| Worked terminal session | A "Done when" first line in every step, with exact output |
| What gets checked | The step's `verify` and its "Done when" line. No separate section |
| Notes | A one-sentence divergence or trap inside the step it affects |
| Hints as questions | Hint 1 names the concept as a question |
| Small stages | At most 10 numbered items per step, one action each |
| Tiny snippet hints | Hint 2 points to the doc section. Hint 3 stays short of the solution line |

## What byox does not copy

CodeCrafters' tester is the product. byox's checks are the learner's own tests, so a step explains what to build in plain words and lets the verify script decide.

## What GreatFrontEnd adds

Read from its free "Accordion in React" question. Different product, same lesson, and it is the model for byox steps.

- **One sentence of goal**, then a **Requirements** list of behaviors, one line each, each testable ("By default all sections are collapsed", "Clicking a title toggles its content").
- **An example** the learner can open and use before they write anything.
- **Notes** on scope: "the focus is functionality, not styling", "you may modify the markup".
- **A hint as a question** ("Can more than one section be open?").
- **Starter files** with the example content already in them, so nobody starts from nothing.
- Difficulty and a recommended duration, shown up front.

byox steps follow this: goal sentence, Requirements (behavior bullets), Example (design image or terminal output), Notes, Starter, then Setup (the commands, numbered).
