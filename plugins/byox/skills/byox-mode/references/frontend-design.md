# Frontend steps

A frontend step is a design handoff, like a ticket at a company. The learner gets a design and builds it by hand. The check is a screenshot compared to the design. No paid design tool is needed.

## Where the design comes from

Use the first that exists.

1. **The mentor's running app.** Check out the solution at the step's tag, start it, and screenshot the page with `byox shot`. Prefer this. It is exactly what the mentor built.
2. **A Storybook story or a component page** in a repo source, shot the same way.
3. **You design it in Penpot.** The source has no usable picture, such as a transcript where the mentor describes the page, or a repo with no UI to run. [Penpot](https://penpot.app) is the open source design tool, with a free account on design.penpot.app or a self hosted instance. The learner gets a real design file they open, inspect and measure. Follow the next section.
4. **You design it in plain HTML.** Use this when Penpot is not connected, so the lesson is never blocked on an account. Follow the section after next.

## Designing in Penpot

Penpot has an official MCP server. It needs three things only the learner can do, so check for them first and never try to work around them.

- A Penpot account, with MCP switched on under Your account, Integrations, MCP Server. The learner generates an MCP key there.
- The client connected, with `npx -y add-mcp -g -n penpot "https://<penpot domain>/mcp/stream?userToken=<their key>"`.
- A Penpot file open in a browser tab, connected through File, MCP Server, Connect. The tab must stay open and active, or the connection suspends.

If the tools whose names start with `mcp__penpot__` are not in your tool list, stop this path. Tell the learner the three steps in one short message, and design in HTML for now. Penpot can write to the learner's file, so work in a file made for the step, make small changes, and say what you changed.

With the connection up:

1. **One file per step, two boards.** Name the file `<course> / <step id> <step title>`. Make a board `Desktop` at 1280x800 and a board `Phone` at 390x844.
2. **Tokens first.** Create the colors, the type styles and the spacing values as named tokens in the file's library, and use only those. The learner reads the design system there. Use system fonts, so the learner's browser draws the same glyphs.
3. **Build with flex layout boards**, not loose rectangles, so spacing is a number the learner can read and copy. Show every state the lesson needs: empty, error, hover and focus.
4. **Export.** Export each board as PNG with the `export_shape` tool, and write the result to `course/tests/<step>/target.png` and `target-phone.png`. The remote server has no access to local files, so the image comes back to you and you write it. Open both images and look at them before you go on.
5. **Hand it over.** Put the file's view link in the step's front matter as `design_url`, so the lesson shows "Open the design in Penpot". Ask the learner for the link when you cannot read it from the file. Write the spec into the lesson's Task: each token with its value, the breakpoint, and each state.
6. **Set the compare to coarse.** Penpot and Chrome draw text differently, so a pixel compare of a Penpot export against a Chrome screenshot fails on font smoothing alone. In the step's verify, set `COARSE=8` and `TOLERANCE=0.02`. That compares 8px block averages, which ignores glyph noise and still catches a wrong color, a missing element or a layout that moved. Check it by running `byox strength`, which must pass on the solution and fail on the previous tag.

## Designing in plain HTML

The fallback is a hand-off the learner can also inspect, with no account.

1. Write `course/design/<step>/design.html`. One self-contained file, no external fonts, scripts or images. Put every color, size and spacing value in CSS variables at the top of the file, so the learner can read the design system in one place. Use system fonts so the screenshot is the same on any machine.
2. Render it with the same tool the check uses, so target and learner page are rendered alike:
   ```bash
   B shot file://$PWD/course/design/<step>/design.html course/tests/<step>/target.png --size 1280x800
   B shot file://$PWD/course/design/<step>/design.html course/tests/<step>/target-phone.png --size 390x844
   ```
   Run these from the project folder. `B` is the path of `scripts/byox`. Skip the phone shot only when the step is desktop only.
3. Write the spec into the lesson's Task section, from the variables in the file: the colors with hex values, the type sizes, the spacing scale, the breakpoint, and what each state looks like. A learner should never need to guess a number.
4. Tell the learner where the design lives, in the step's instructions: "Open `course/design/<step>/design.html` in the project folder in your browser and use Inspect, like a design file." The site also shows the two target images in the step.
5. Build the solution from the design, not the other way round. The solution's page must match the target within the tolerance, and `byox strength` checks that the previous tag does not.

A design is good when a stranger could build it from the images and the spec alone. Do not leave out a state to make the solution easier.

## Pixel rules that keep the check fair

- The check compares at a fixed size: 1280x800 for desktop and 390x844 for phone. Say both in the task.
- Anything that changes between runs breaks a pixel diff: dates, random avatars, animations and carousels. Fix them in the design, or have the page hide them under `?byox=1`, and say so in the task.
- Use `--tolerance 0.03` to start. For text-heavy pages or any Penpot design, add `--coarse 8` instead of raising the tolerance. A tolerance above `0.08` means the check is not testing much.
- Fonts: a design that needs a web font makes the learner's screenshot differ by machine. Use system fonts or ship the font file in the step.
