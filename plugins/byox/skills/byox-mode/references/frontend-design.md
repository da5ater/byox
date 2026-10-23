# Frontend steps

A frontend step is a design handoff, like a ticket at a company. The learner gets a design and builds it by hand. The check is a screenshot compared to the design. No paid design tool is needed.

## Where the design comes from

Use the first that exists.

1. **The mentor's running app.** Check out the solution at the step's tag, start it, and screenshot the page with `byox shot`. Prefer this. It is exactly what the mentor built.
2. **A Storybook story or a component page** in a repo source, shot the same way.
3. **You design it.** The source has no usable picture, such as a transcript where the mentor describes the page, or a repo with no UI to run. Follow the next section.

## When you design it

You are the designer. Make a design file that is a real hand-off: concrete, measurable and inspectable.

1. Write `course/design/<step>/design.html`. One self-contained file, no external fonts, scripts or images. Put every color, size and spacing value in CSS variables at the top of the file, so the learner can read the design system in one place. Use system fonts so the screenshot is the same on any machine.
2. Render it with the same tool the check uses, so target and learner page are rendered alike:
   ```bash
   B shot file://$PWD/course/design/<step>/design.html course/tests/<step>/target.png --size 1280x800
   B shot file://$PWD/course/design/<step>/design.html course/tests/<step>/target-phone.png --size 390x844
   ```
   `B` is the path of `scripts/byox`. Skip the phone shot only when the step is desktop only.
3. Write the spec into the lesson's Task section, from the variables in the file: the colors with hex values, the type sizes, the spacing scale, the breakpoint, and what each state looks like. Name the states the design shows, such as empty, error and hover. A learner should never need to guess a number.
4. Tell the learner where the design lives, in the step's instructions: "Open `course/design/<step>/design.html` in your browser and use Inspect, like a design file." The site also shows the two target images in the step.
5. Build the solution from the design, not the other way round. The solution's page must match the target within the tolerance, and `byox strength` checks that the previous tag does not.

A design is good when a stranger could build it from the images and the spec alone. Do not leave out a state to make the solution easier.

## Pixel rules that keep the check fair

- The check compares at a fixed size: 1280x800 for desktop and 390x844 for phone. Say both in the task.
- Anything that changes between runs breaks a pixel diff: dates, random avatars, animations and carousels. Fix them in the design, or have the page hide them under `?byox=1`, and say so in the task.
- Use `--tolerance 0.03` to start. Raise it for text-heavy pages, since font rendering differs a little between machines. A tolerance above `0.08` means the check is not testing much.
- Fonts: a design that needs a web font makes the learner's screenshot differ by machine. Use system fonts or ship the font file in the step.

## Optional: Penpot

[Penpot](https://penpot.app) is the open source design tool. It has free hosted accounts and can be self hosted with Docker, and community MCP servers let an agent create designs in it. byox does not depend on it, because a learner needs an account and a running instance. If the learner already uses it, export the frames as `target.png` and `target-phone.png` and put the share link in the task.
