# Solution lock

## Sub-features

- Show solution shows the mentor's diff per step, with `generated:` files collapsed.
- Compare shows the learner's code against the solution.
- Both unlock when the lesson is green or skipped.

## How to get to it (user POV)

At the bottom of a green or skipped lesson, click Show solution or Compare with my code.

## Driving it with curl

- Before green, `GET .../lessons/01-ping/solution` returns 403.
- After both steps are green, it returns 200 with `steps[].files[].patch`.
- `POST .../lessons/01-ping/skip` on a fresh fixture also unlocks it, and the skip lands in the weakness log in `vault/Courses/mini-redis.md`.

## Gotchas

- The solution repo is `course/solution`, ignored by the learner's repo. Read it only through these routes.
