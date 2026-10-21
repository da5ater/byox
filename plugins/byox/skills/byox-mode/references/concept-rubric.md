# Concept rubric

Concept pages are the Go deep links. There is one global library in `<vault>/Concepts/`, shared by every course, so a concept like authorization is written once. The owner lesson's writer creates a page with the `byox-teach` skill. The owner lesson's reviewer checks it against this rubric.

## Shape

```markdown
---
title: Cookie sessions
origin: corsego/03-authentication
aliases: [session cookie]
resources:
  - url: https://guides.rubyonrails.org/security.html#sessions
    section: "2 Sessions"
---

## The problem

## How it works

## A tiny example

## What Devise does for you

## Gotchas

## Diagrams
```

The six headings appear in this order. The fourth starts with "What " and names the gem or framework. Lint checks the headings. The site appends "Where it shows up" from every lesson that lists the concept, so never write that section.

## What each section holds

1. **The problem.** What breaks without it. Show the failure, such as a user who logs in and is a stranger again on the next request.
2. **How it works.** The mechanism, step by step, with no metaphors.
3. **A tiny example.** Outside the project, small enough to type in a few minutes. Sessions by hand in a 20-line Rack app, before Devise.
4. **What the gem does for you.** What it does, and what it hides from you.
5. **Gotchas.** Common misconceptions and edge cases, each one concrete.
6. **Diagrams.** A series of mermaid diagrams. Each one redraws the last and adds one part. Never one diagram with every part at once.

## Calibration

Read `<vault>/learner-profile.md` first. Skip what the learner already knows. Spend the words on what they are learning.

## Review questions

The reviewer answers each with yes or no. Every no gets fixed.

1. Does the page start with a plain definition a senior engineer would say out loud?
2. Does The problem show a concrete failure, not a claim?
3. Does How it works describe the mechanism with no metaphor?
4. Could the learner type the tiny example in under ten minutes, outside the project?
5. Does the What section name what the gem hides?
6. Is every gotcha specific to this concept?
7. Do the diagrams build up one part at a time?
8. Does every linked resource pass `resource-rules.md`?
9. Is anything on the page something the learner profile says they know? It should not be.
10. Is the prose plain, with short sentences, no filler, no em dashes, and one name per idea?
