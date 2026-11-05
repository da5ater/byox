# Stack wizard

Run this at the very start of a compile, before the outline and before any lesson. It settles the folders, the stack and the architecture, because every step the learner reads names them. Use `AskUserQuestion`, at most 4 questions per call, with the recommended option first. Batch 1 Q2 and Batch 4 Q3 are always asked, even when the source answers them: put the detected answer first, labelled `(detected from source)`. They usually ride in round 2 of `learner-intake.md`. Skip any other question the source already answers, and say what you assumed. The learner can always pick Other and type their own.

## Batch 1: shape

1. **Architecture.** One program, API plus frontend (two projects), a monorepo with shared packages, or services (one project per service). Each project becomes a folder in `work/` and an entry in `projects:`. Name the folders now: `api`, `frontend`, `worker`.
2. **Source stack.** Keep the source's stack, or port it. Default: port to current versions. Read `porting.md` before answering for them.
3. **Language per project.** TypeScript or JavaScript for node projects, plus the runtime version. Ruby, Python, Go and the like follow the source.

## Batch 2: frontend, when a project has one

1. **Framework and build tool.** React with Vite, Next.js, Vue, Svelte.
2. **Styling.** Tailwind, CSS modules, plain CSS.
3. **UI kit.** shadcn/ui on Radix, shadcn/ui on Base UI, MUI, none. Name the init choices in the lesson that installs it: base color, CSS variables, components folder.
4. **Routing and data.** React Router or the framework's own. The HTTP client: `fetch`, axios or TanStack Query. Record it as `http_client`, and write the course's tests so they pass whichever client the learner picks, by faking the network below the client, never one client's function.

## Batch 3: backend, when a project has one

1. **Framework and API style.** The source's, as REST or GraphQL.
2. **Database.** The source's, or SQLite for a local course.
3. **Auth.** Sessions, JWT, a hosted provider.

## Batch 4: checks

1. **Test runner per project.** Default: the source's for a backend, Vitest for a Vite frontend.
2. **Designs.** `penpot-diff`: a Penpot frame per UI step, checked by a coarse screenshot compare. `penpot`: a Penpot frame per UI step, checked by DOM tests only. `html`: a design built in plain HTML. `none`: text steps only. Anything but `none` means every `ui` or `visual` step needs a `design_url`, or a `design_exempt` reason, and `byox lint` enforces it.
3. **Stand-ins.** List every external service (payments, email, storage, OAuth), every private or internal library the learner cannot install, and every sibling service the course does not build. Propose a mode for each: `real`, `free_tier`, `sandbox`, `stub`, or `learner_writes` (the learner builds a small version in a named lesson). Show it as one table, name, kind, mode and what the learner will see, and get a yes. Record each row in `services:` as `{name, kind: service|library, mode}`.

## Plan before any lesson

The wizard is a planning session, not a form. Before the outline, settle three things and write them down, because every step names them:

- **Folders.** Which projects exist and what each folder is called (`work/api`, `work/frontend`).
- **Stack.** Language, framework, build tool, UI kit, test runner, per project.
- **Architecture.** How the projects talk to each other, and whether the learner wants to change it (services, a monorepo).

The UI kit is used from the first step that draws anything. If the kit is shadcn/ui, step one of the frontend installs it and builds with its components. `byox lint` reports a first UI step that does not (`ui_kit`).

## Record it

Write the answers into `course.md`, so lint and the writers read the same facts:

```yaml
projects:
  - {name: api, source: ".", description: Rails API}
  - {name: frontend, source: frontend, description: React app}
stack:
  original: Rails 6.0, Webpacker, jQuery
  target: Rails 8.1 API, React 19 with TypeScript on Vite, Tailwind, shadcn/ui
  ported: true
  test: rspec, vitest
  choices:
    language: ruby (api), typescript (frontend)
    architecture: api plus frontend
    ui_kit: shadcn/ui, radix, neutral, css variables
    design: penpot
```

`language`, `architecture` and `design` are required. Add any other key a lesson depends on. Show the learner the recorded block and the stand-ins table and get a yes before the outline. Then set `stack.confirmed: true`. Only the learner's yes sets it, and `byox lint` refuses an approved course without it or without a `services:` list (an empty list is fine).
