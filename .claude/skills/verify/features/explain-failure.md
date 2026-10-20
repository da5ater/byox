# Explain failure

## Sub-features

- After a red Verify, Explain failure streams the coach's answer: what it means, where to look, what to read.
- The coach runs in a throwaway dir with the lesson (revealed hints only), the failure, the learner's diff and concept pages.
- Read deny rules wall off `course/solution` and `course/source`, even by absolute path.

## How to get to it (user POV)

Verify a step and fail. Click Explain failure under the red output.

## Driving it with curl and the real agent

1. Fixture with the default `agent_cmd` (`claude -p`).
2. Write a wrong `main.rb`, such as one that prints `pong` in lower case. Verify `01.1` and get red.
3. `curl -sN -X POST .../steps/01.1/explain`. Expect three parts in the streamed text and no fenced code block.
4. Leak probe: put a unique token in a comment in the solution repo's `main.rb` at a tag, then ask through a modified prompt or check the argv for the `Read(//.../course/solution/**)` deny rule. The token must never appear.

## Gotchas

- A real run takes 20 to 90 seconds and costs tokens. Use a recording script as `agent_cmd` when you only need the argv.
- One agent job per course at a time. A second returns 409.
