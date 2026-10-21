# Obsidian layout

The vault folder is `vault:` in `<root>/byox.yml`. The default is `/home/mohamed/ObsidianVault/1- resource/buildYourOwnXLessons`.

## byox.yml

```yaml
vault: /home/mohamed/ObsidianVault/1- resource/buildYourOwnXLessons
agent_cmd: claude -p
```

Both keys are optional. `agent_cmd` is the command every agent button runs. Swap it here and nowhere else.

## Folder

```
<vault>/
  Concepts/<slug>.md       shared concept pages, see concept-rubric.md
  Courses/<slug>.md        progress and weakness log, generated
  learner-profile.md       what the learner already knows
  resource-blocklist.md    links the learner flagged
```

## Courses/<slug>.md

The site regenerates it whole from `course/state.json` after every state change. `byox sync` does the same for every course. Never edit it by hand. It holds the progress line, a course map table and the weakness log: skips, steps where all three hints were used, steps with five or more verify attempts, explain requests, and Unclear, Broken and Bad resource notes.

## learner-profile.md

```markdown
## Knows

- Ruby and Rails CRUD
- SQL joins

## Learning

- Authentication and authorization
- Background jobs
```

Writers and reviewers read it to skip what the learner knows. The site never writes it.

## resource-blocklist.md

One line per link. Only the site writes it, when the learner presses Bad resource.

```
- https://example.com/thin-page | 2026-10-21T09:41:00Z | corsego/05-pundit
```
