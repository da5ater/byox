# Start a course

The user wants to open their courses. `B` is the absolute path of `scripts/byox` next to `SKILL.md`.

1. **Find the root.** `$BYOX_ROOT`, else `~/byox-courses`. Create it if it is missing. Read `<root>/byox.yml` if it exists. Write it only when the user wants a vault or an agent command other than the defaults in `references/obsidian-layout.md`.
2. **Prepare the vault.** Make sure `Concepts/`, `Courses/`, `learner-profile.md` and `resource-blocklist.md` exist in the vault. If `learner-profile.md` is empty, ask the user once what they already know and what they are learning. Write it in the shape `references/obsidian-layout.md` gives.
3. **Start the site.** Run `B site` in the background. If it says another site is running, one already is, so give its URL. The default is `http://127.0.0.1:4917`.
4. **Reply** with the URL and the daily loop in two sentences. Open the site, read the lesson, write code in your editor, press Verify. Green means go to the next step.
