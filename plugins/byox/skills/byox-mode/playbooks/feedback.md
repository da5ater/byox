# Ship feedback as a pull request

Run by the `feedback` agent. `B` is `skills/byox-mode/scripts/byox` in the repo you change. `R` is the courses root. `UP` is the upstream repo, `da5ater/byox` unless `R/byox.yml` sets `upstream:`. The prompt gives you `R`, `UP`, and the local checkout when there is one. Anyone who uses byox can run this playbook, not only the maintainer.

1. **Read the open items.** `B feedback list --open --root R`. If there are none, stop.
2. **Check GitHub.** `gh auth status` must show a logged-in account. Otherwise stop and tell the learner to run `gh auth login`. `ME` is `gh api user -q .login`.
3. **Get a checkout of `UP`.** `REPO` is the local checkout from the prompt. Without one, `REPO` is `R/.byox/byox-src`: clone it with `gh repo clone UP R/.byox/byox-src` the first time, and `git -C REPO fetch origin` after that. In `REPO`, `git status --porcelain` must be empty. Otherwise stop and report why.
4. **Decide where the branch goes.** `gh repo view UP --json viewerPermission -q .viewerPermission`. ADMIN, MAINTAIN or WRITE push to `origin`, and `HEAD_OWNER` is the owner of `UP`. Anything else forks: `gh repo fork UP --remote --remote-name fork` once, then push to `fork`, and `HEAD_OWNER` is `ME`.
5. **Branch.** `D` is today's date, `YYYY-MM-DD`. Create a worktree for the branch `feedback/D` from `origin/main`: `git -C REPO worktree add ../byox-feedback-D -b feedback/D origin/main`. Add `-2`, `-3` to the date when the branch exists. `W` is the worktree path. Do all edits in `W`.
6. **Pick a page for each item.** Use the item's `page`. A page under a real course, `#/c/<slug>/...`, needs that course. Copy `R/<slug>` without `course/source/upstream` into a scratch root, with a `byox.yml` that points `vault:` at a scratch copy of the vault's `Concepts/`. Anything else uses the fixture: `ruby W/plugins/byox/skills/byox-mode/scripts/test/fixtures/make_mini_redis.rb <scratch>`. Write down how to reach the state the item is about, such as a revealed hint or a red Verify, as `curl` calls to the site's API.
7. **Before screenshots, from the code on `main`.** Start `ruby W/plugins/byox/skills/byox-mode/scripts/byox site --root <scratch> --port 4931` from a clean checkout of `origin/main`, which `W` is before your first edit. Record its PID. Reach each item's state, then for each item:
   ```bash
   playwright screenshot --viewport-size=1280,800 --wait-for-timeout=1500 "http://127.0.0.1:4931/<page>" W/docs/feedback/D/<id>-before.png
   ```
   Add a phone shot at `--viewport-size=390,844` named `<id>-before-phone.png` when the item is about layout. Stop the site by its PID.
   If `playwright` says its browser executable does not exist, run `playwright install chromium-headless-shell` once. Without Playwright, any Chrome or Chromium works: `<chrome> --headless=new --hide-scrollbars --window-size=1280,800 --virtual-time-budget=3000 --screenshot=<file> "<url>"`.
8. **Make each change.** One item at a time. Write a failing test first when the item is behavior a test can see. Use the existing tests' style. A pure look-and-feel item is proven by its screenshots. Run `ruby W/plugins/byox/skills/byox-mode/scripts/test/run.rb` after each item. It must stay green. Commit each item on its own: `Feedback <id>: <what changed>`. If you cannot do an item, write down why and move on.
9. **After screenshots, from `W`.** Use a fresh scratch root built the same way as in step 6. Start the site from `W` on port 4932, reach the same states, and take the same shots named `<id>-after.png` and `<id>-after-phone.png`. Stop it by its PID.
10. **Write the log.** `W/docs/feedback/D/README.md` has one section per item: the learner's words, the page, what changed, and the before and after images by relative path. Commit it with the screenshots.
11. **Push and open the pull request.** Push to the remote from step 4: `git push -u origin feedback/D` or `git push -u fork feedback/D`. Write the body to a file and run `gh pr create --repo UP --base main --head HEAD_OWNER:feedback/D --title "Feedback D: <n> items" --body-file <file>`. The body has, per item:
   - the learner's words as a quote, and the page,
   - what changed, in two or three sentences,
   - a two-column table, Before and After, with each image as `![before](https://github.com/HEAD_OWNER/byox/blob/feedback/D/docs/feedback/D/<id>-before.png?raw=true)`, so the images load from the branch the pull request comes from,
   - the tests that prove it, if any.
   Then a "Not done" section for skipped items with the reason, and "How to try it" with the commands to run the site from the branch.
12. **Mark the shipped items.** `B feedback mark <ids> --pr <url> --root R`. Skipped items stay open.
13. **Clean up.** Confirm no process you started still listens on 4931 or 4932. Remove the scratch roots by their literal paths. Remove the worktree with `git -C REPO worktree remove W`. The branch stays on GitHub for review.
