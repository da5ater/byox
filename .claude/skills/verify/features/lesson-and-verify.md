# Lesson and Verify

## Sub-features

- Lesson sections in DESIGN order: goal, short read, task, tests in plain English, steps, resources, Go deep, solution.
- Steps unlock in order. Verify streams output and turns the step green on exit 0.
- The last green step turns the lesson green and shows `#celebrate` with Next lesson.
- The course map and the vault course note update.

## How to get to it (user POV)

Open the site, click the course card, click Continue or the first lesson.

## Driving it with curl and the browser pane

1. `GET /api/courses/mini-redis/lessons/01-ping` shows step `01.1` open and `01.2` locked.
2. With no `main.rb`, `POST .../steps/01.1/verify` ends `{"ok":false,...}`.
3. Write the `01.1` solution to `main.rb`. Verify ends `{"ok":true,"step_status":"green"}`.
4. Write the `01.2` solution. Verify `01.2` ends with `"lesson_green":true`.
5. In the browser, click `button[data-verify="01.2"]` and see `#celebrate`.

## Gotchas

- Verify runs the command in the step's `verify:` with the course dir as cwd. A verify that needs a server must start and stop it itself.
- Green is sticky. Breaking the code after green does not turn a step red.
