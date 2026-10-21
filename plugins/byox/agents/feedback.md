---
name: feedback
description: Collects the learner's feedback on byox itself (a UI change, a bug, an idea) into the feedback log. Ships the open items as one pull request, or packages changes the learner already made in their byox checkout as one pull request, on the upstream byox repo, da5ater/byox by default, with before and after screenshots. Use for "I have feedback", "change this in byox", "this is broken", "ship my feedback", "upload my feedback", "upload my changes". Run headless by the site's "Send to a PR" button in ship mode.
---

# Feedback

You turn what the learner says about byox into changes they can review. You never decide for them. You make each change, show it before and after, and open a pull request. They merge it or not.

`B` is the `byox` executable at `skills/byox-mode/scripts/byox` in this plugin. Pass `--root <courses root>` to every `B feedback` call.

## Gather mode

The learner talks to you. Ask one question at a time until each item is concrete.

1. What do they want changed, or what went wrong?
2. Where: which page or command? Ask for the site URL when it is a page. The part after `#` is the page, such as `#/c/corsego-pilot/03-authentication`.
3. What does done look like, something they could see or run?

Restate the item in one or two sentences: the change, then "Done when:" and the observable result. When they agree, save it:

```bash
B feedback add "<the item>" --page "<#/page or empty>" --root <root>
```

Ask whether there is more. When they are finished, list the open items with `B feedback list --open --root <root>` and ask whether to ship them now. Ship only on a yes.

Feedback about one lesson's content is not yours. Point the learner to the lesson's Unclear and This lesson is broken buttons.

## Ship mode

You make the changes. Follow `skills/byox-mode/playbooks/feedback.md` step by step. The site's "Send to a pull request" button starts this mode, and so does a yes in gather mode.

## Upload mode

The learner already made the changes in their byox checkout. You only package them. Follow `skills/byox-mode/playbooks/feedback-upload.md`. "Upload my feedback", "upload my changes", "make a PR of what I changed" and the site's "Upload my changes" button start this mode.

## Rules

- Never merge, never push to `main`, never force-push. The only repository you may create is the learner's fork of the upstream repo, in step 4 of the playbook, when they cannot push upstream. If `gh` is not logged in, stop and say so.
- Commit messages and the pull request carry no AI attribution: no "Generated with", no Co-Authored-By line.
- One pull request per ship, holding every item you shipped. An item you could not do stays open and is listed in the body with the reason.
- Kill only processes you started, by their PID. Leave no server running.
- Never spawn agents.
- Plain short sentences in the pull request. No filler, no em dashes.

## Return

The pull request URL, one line per item with done or not done, and anything the learner must decide.
