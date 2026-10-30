---
name: byox-short-read
description: Writes the Short read of a byox lesson as a friendly ticket a learner can follow with no background. Plain words first, then the two or three ideas the lesson needs. Use before writing or rewriting any lesson's Short read, and when a learner says the Short read is hard to follow.
---

# Short read

The Short read is the ticket the learner picks up. After a minute they know what they are building, why it exists, what they will see when it works, and the two or three ideas they need. It is a Jira ticket in friendly words, not a lecture and not a stack list.

It follows the `bro` rule: say it the way one person would to another, with no jargon. It follows `learn-before-task`: the problem first, then only the ideas the task cannot be done without, each tied to this lesson's real files.

## The shape

Write these four parts in order, with a blank line between them. No headings inside the section. Bold the first words of each part.

1. **What you're building.** One sentence of what exists when the lesson is done, then what the learner will see: a page, a terminal line, a number. Name the real thing: "a page that lists courses", not "a data layer".
2. **Why it matters.** Two sentences. Who is stuck without it, and what breaks. Start from the symptom: "A browser cannot show JSON, so right now your API has no face."
3. **Ideas you need.** Two or three. Each is its plain meaning in one sentence, then where it shows up in this lesson, in code format only after the plain words. Example: "Props are the values a parent hands to a component, like the title you pass to a card. You will pass `title` and `price` in 03.1."
4. **What differs from the mentor.** Only when something does, in one or two sentences, so a learner who watches the video is not confused.

## Rules

- At most 200 words, not counting code blocks. `byox lint` enforces it (`short_read_size`).
- Sentences of 20 words or fewer. One idea each.
- No term before its plain meaning. A tool name appears only where the learner will touch it. Never list the whole stack in one sentence.
- Give a picture: one tiny example, one line of expected output, or an analogy from everyday life. An abstract definition alone does not stick.
- Concrete over abstract. Tie every idea to a file, a page or a number in this lesson. An idea with no link to the lesson does not belong.
- Do not repeat the steps. The Short read says what and why. The Task says how.
- Never put solution code in it.
- End with nothing: no summary, no "let's get started".

## Check yourself before saving

Read it as someone who knows nothing about the lesson. Can they say in one sentence what they will build and what they will see? If not, rewrite part 1. If a word needs a dictionary, replace it.
