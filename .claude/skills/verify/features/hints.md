# Hints

## Sub-features

- Three hints per step, revealed in order. The lesson JSON carries only revealed hints.

## How to get to it (user POV)

On an open step, click "Hint 1 of 3", then the next.

## Driving it with curl

- `POST .../steps/01.1/hints/2` before hint 1 returns 409 with `reveal hint 1 first`.
- `POST .../steps/01.1/hints/1` returns 200 with one hint.
- `GET` the lesson. Step `01.1` has exactly one hint in `hints`.
- Hints on a locked step return 409.

## Gotchas

- The hint count lives in `state.json` and never goes down.
