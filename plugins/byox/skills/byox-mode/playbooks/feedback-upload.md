# Upload my changes as a pull request

Run by the `feedback` agent in upload mode. The learner already changed byox in their checkout. You do not re-implement anything. You package their work so a reviewer can see it and try it in minutes.

`REPO` is the learner's byox checkout, `plugin_repo` in `R/byox.yml`. `R` is the courses root. `UP` is the upstream repo. The prompt gives you all three. Steps 2, 4, 6, 7 and 9 to 11 of `feedback.md` describe the shared mechanics. Use them as written there.

1. **See what changed.** `BASE` is `origin/main` when it exists, else `HEAD`. Read `git -C REPO status`, `git -C REPO diff BASE`, and `git -C REPO log BASE..HEAD`. Read the open items in the feedback log as the learner's notes on why. If nothing changed, stop.
2. **Group the work into items.** One item per change a reviewer would judge on its own, such as "bigger Verify button" or "lint rule for empty hints". For each item, write what changed and why. Take the why from the learner's notes or commit messages. In gather mode, ask the learner when the why is unclear. Headless, write your best reading and mark it "(inferred)".
3. **Run the tests on the learner's work.** `ruby REPO/plugins/byox/skills/byox-mode/scripts/test/run.rb`. Never fix a red test yourself. Record the result for the pull request.
4. **Branch and commit.** `D` is today's date. `git -C REPO switch -c feedback/D`, adding `-2` and up when it exists. The learner's uncommitted work moves with the switch. Commit each item on its own with `git add <its files>`. The message names the change, with no AI attribution. Their earlier commits stay as they are.
5. **Before and after.** For each item that changes something a learner sees, such as the site, a lesson page or CLI output, show it twice. Pages: a worktree of `BASE` for the before shots and the branch for the after shots, built and shot as in steps 6 to 9 of `feedback.md`, saved under `docs/feedback/D/`. CLI output: run the same command on both and keep the two outputs as text. Items no one can see, such as a refactor, get a one-line note instead.
6. **Write how to test it.** In `docs/feedback/D/README.md`, one section per item: what changed, why, the before and after, and how to try it. Start with the setup a reviewer runs once:
   ```bash
   gh pr checkout <number> --repo UP
   ruby plugins/byox/skills/byox-mode/scripts/test/run.rb
   ruby plugins/byox/skills/byox-mode/scripts/test/fixtures/make_mini_redis.rb /tmp/byox-try
   ruby plugins/byox/skills/byox-mode/scripts/byox site --root /tmp/byox-try --port 4999
   ```
   Then per item: the URL to open, what to click or run, and what they should see. Commit the folder.
7. **Open the pull request.** Use steps 2 and 4 of `feedback.md` to pick `origin` or a fork, then push and run `gh pr create` as in step 11. The body is the README's content, with images as absolute `?raw=true` links on the head branch, plus a Tests line: green, or red with the failing test names. When `REPO` has no GitHub remote, stop after step 6. Write the body to `docs/feedback/D/PR.md`, commit it, and tell the learner the branch is ready to push once the repo has a remote.
8. **Close the loop.** Mark the feedback items this pull request covers: `B feedback mark <ids> --pr <url> --root R`. Switch the learner back with `git -C REPO switch main`, and tell them their work now lives on `feedback/D`. Stop every server you started and remove every scratch dir and worktree you made, by their literal paths.
