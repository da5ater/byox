---
name: byox-task-writing
description: Writes the Task and the steps of a byox lesson as a light, friendly work ticket with room to breathe. One action per item, a checkpoint to look at, hints as questions, and a learning order from follow-along to your-own-change. Use before writing or rewriting a lesson's Task, steps, instructions and hints, and when a learner says the steps feel crowded.
---

# Task and steps

A step is a small work ticket. The learner should know what done looks like before they type anything, and should never face a block of text with eight things in it.

Open `references/codecrafters-patterns.md` once. It shows the CodeCrafters and GreatFrontEnd patterns this skill follows.

The model is a Jira ticket made friendly: a title, why it matters, a "done when" the learner can see, and a short checklist. CodeCrafters stages show the same thing: say what you will do in one plain sentence, show the exact input and output, give a tiny worked example, then hint with questions. Read `references/codecrafters-patterns.md` once for the details.

## The Task section

Short. It lists each step with its id and one line of what is true when it is done, in plain words. It is the map, not the manual. Never a spec paragraph per step.

## A step

Modeled on how GreatFrontEnd writes a question, because it is deterministic: the learner can tell at every line whether they are done. A step reads like this, in this order, with a blank line between parts:

1. **The goal, one sentence.** "Build the `Navbar` component: a labeled navigation bar with the brand, two links and a search box." Verb first, one thing.
2. **Requirements.** Three to seven bullets, each one observable behavior, each one line. Name the exact inputs and outputs: what the client sends, by field name, and what comes back, by status and keys. "A beneficiary posts `phone_number`, `identity_reference` and `password` to `/retail/sessions`." A requirement that says only "with the right password gets 200" leaves the learner guessing what is sent. Written as what is true, not what to type. "The brand link says Corsego and goes to `/`." "Submitting the search form does nothing yet." No bullet says how to code it. These are what the step's check looks at, so a learner can tick them off.
3. **Example.** What done looks like: the design image or Penpot board, or the exact terminal session with its output. When a design exists, say which numbers to read from it. A terminal example runs from a fresh start of this step: every value it uses, such as a token or an id, is made by an earlier command in the same example. Never `$TOKEN` without the command that gets it. The learner runs the example after the Requirements to see the code work, so it must work when pasted as is.
4. **Notes.** One or two bullets of scope, as GreatFrontEnd does: what to ignore ("styling is not checked here, match the design after the tests pass") and what you may change ("you may rename the props"). Also the one trap worth a line, and any divergence from the mentor.
5. **Starter.** What already exists that they build on, by file name ("`src/App.tsx` already renders `<Navbar />`"). A learner never starts from a blank page when the step needs a hook to hang on.
6. **Setup.** Last, because it is the part you follow with the other parts open beside it. Only when there is something to run or install: numbered items, one command each, each in its own code block, with the folder named (`work/frontend`). Skip it when there is nothing. Setup is scaffolding the requirement does not test: `rails new` with its flags, adding the test framework, creating the database. Anything a requirement depends on is the requirement's own work and never Setup: the model the step is about, its columns, and a gem the behavior needs (bcrypt for `has_secure_password`). Name those in Requirements and let the learner do them.
7. **Read first** is not prose. It is the step's `read_first` field. See `byox-read-first`.
8. **Real code** is not prose either. It is the step's `real_code` field: one to three links to where the real codebase did this step, the pull request first, then the file at its lines. The learner opens them after the step is green to compare their code with the team's.

The old numbered recipe, twelve items long, is gone. Setup keeps numbers because commands run in order. Everything else is bullets about behavior, so there is no wall to climb and nothing hidden in the middle of a sentence.

Use the course's UI kit from the first step that draws anything. If `stack.choices.ui_kit` names shadcn/ui, the step that first builds a component installs it and builds with its parts (`Button`, `Input`, `NavigationMenu`). Never build a plain Tailwind version first and swap it later.

Checkpoints still apply: after at most five setup items, say what to run and what to see. A step has at most 10 numbered items and 40 words per item (`byox lint` enforces both).

## Make it teach

Use the order learners actually improve in, not only the order the code is built.

- **Early steps: follow and explain.** Show a worked example, then ask the learner to repeat it with their own name or value. Ask them to say what each part does (understand).
- **Middle steps: apply.** Give the goal and the file, leave the typing to them. Hints cover the gap.
- **Late steps: predict, then change.** Ask "What will this print? Write your guess, then run it." Then ask for a small change of their own (analyze, create). The gap between guess and result is where learning happens.
- **Fade the help.** The first step of a kind spells more out. The next one of the same kind names the goal only.
- **One new thing per step.** If a step teaches two ideas, it is two steps.

## Write it the way the team wrote it

The goal is to think like the people who wrote the source, not only to make the check pass. When the source puts logic in a service object, a concern, a policy or a job, the step asks for the same shape with the same name, and one line under Notes says why the team chose it: "The real code keeps sign-in in `Retail::UserSessions::Dispatcher`, a service object, so the controller only renders. Keep yours the same." Use the source's gems, its error responses and its logging the same way, once the course's ring reaches them.

A course grows ring by ring and drops nothing. When the source does more than this step builds, say which ring it comes in, never that it is left out: "The real sign-in also tracks devices. That comes in ring 2." Report each such item to the lead, who lists it under `deferred:` in `course.md`. `byox lint` flags "leave out" and "out of scope" in a lesson.

## Hints

Three, as `course-format.md` says, written as questions the learner can answer.

1. Names the concept as a question: "How do you tell whether the line starts with `echo`?"
2. Says where to look: the function, the doc section.
3. Nearly gives it away but never a full line of the solution. When `generators` already list the commands, hint 3 covers only what is left to work out. It never repeats a command.

## Writing rules

- Plain, short sentences. No filler, no em dashes.
- Say "you". Say what you will see, not what the system does internally.
- Exact names: file path, command, expected output. Never "set it up" or "configure it".
- Divergences from the mentor go in the step they affect, one sentence.
- Never solution code in prose or hints.
- A learner who has never seen the tool should still know what to type next.

## Before saving

Check: a one-sentence goal first, Requirements as three to seven behavior bullets, an Example, setup items at most 10 and 40 words each, a checkpoint at least every five setup items, each hint a question. Then read the step aloud. If you run out of breath inside one item, split it.
