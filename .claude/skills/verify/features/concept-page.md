# Concept page

## Sub-features

- Go deep links on the lesson open `#/concept/<slug>`.
- The page renders from `<vault>/Concepts/<slug>.md`, with mermaid diagrams and a "Where it shows up" list of lessons.

## How to get to it (user POV)

On a lesson, under Go deep, click a concept.

## Driving it with curl and the browser pane

- `GET /api/concepts/stdin-loop` returns the page and the lessons that use it.
- In the browser, the page shows rendered SVG for each mermaid block.

## Gotchas

- Mermaid loads from jsdelivr on demand. Offline, the diagram shows as code.
