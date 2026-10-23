# Porting

A course is ported when `stack.ported` is true in `course.md`, such as Corsego moving from Rails 6 to Rails 8.1. The step's tests define the behavior. The port is checked by a script, not by reading it.

## Order for each step

1. Write the step's tests from the behavior of the mentor's diff, on the target stack.
2. Start the solution worktree from the previous step's tag. The first step of lesson 1 starts from `base`, an empty tree.
3. Port the mentor's code for the step. Keep the mentor's names, files and structure unless the target stack forces a change.
4. Run the step's verify in `course/solution`. It must pass.
5. `byox tag <course> <step>`. Then `byox strength <course> --step <step>` must print `ok`.

## Run every generator yourself

Port by running the same generator commands the step lists, in the solution worktree, with the same Ruby or runtime the learner will use. Then read what each one prints and diff what it wrote. The Corsego pilot found three things this way that no amount of reading the transcript would show.

- The target stack may already do what the mentor did by hand. Rails 8.1 writes the mailer's `default_url_options` in development, so Devise's "add this" step becomes "check it is there".
- A generator may leave a file that breaks the step's tests. Devise's `users.yml` fixture holds two empty users that collide on the unique email index.
- A CLI bound to another Ruby skips post-install steps silently. `rails new` run through a `#!/usr/bin/ruby` binstub left out importmap, Turbo and Stimulus.

Each finding becomes an instruction or a hint in the step.

Writers of a ported course run in lesson order, because lesson N's port starts from lesson N-1's last tag.

## What may change

- Framework idioms the target stack replaced. Webpacker becomes importmap. `link_to ... method: :delete` becomes `button_to ... method: :delete` without jQuery UJS.
- Gem versions and their new APIs.
- Generator flags.

## What may not change

- Features, their order, and their visible behavior.
- The mentor's domain names: models, routes and columns.

Name every change in the step's instructions, so the learner knows why their code differs from the video. The solution view shows the ported code, with `course/source/diffs/<step>.diff` as the original diff.
