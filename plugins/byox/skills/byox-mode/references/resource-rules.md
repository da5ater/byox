# Resource rules

Each lesson has two resources, a primary and a backup. Each concept page links the resources it relies on. A human-written explanation beats an agent's.

## Rank by type

1. A teaching article.
2. A named book chapter with a page range.
3. A video with timestamps.
4. Official docs, only when they are teaching-grade, such as the Rails Guides or the Tailwind docs.

API reference is never a resource. A gem's README sits at most at the backup tier.

## Check every candidate

Open it and read it. Then check all of these.

- It explains this lesson's concept, not a neighbor of it.
- It matches the stack version closely enough. A Rails 4 article on `before_filter` fails for Rails 8.
- It is not a thin SEO page, a listicle, or a page that mostly links elsewhere.
- It is not in `<vault>/resource-blocklist.md`.
- The link resolves. `byox lint` fails a dead link.

## Write it down

```yaml
- url: https://guides.rubyonrails.org/security.html#sessions
  section: "2 Sessions, up to 2.3"
  why: Explains what a session cookie holds and why Rails signs it.
```

- `section` points at the exact heading, page range or timestamps. Never a whole site.
- `why` is one line on why this one, for this lesson.

## When the learner flags one

Bad resource adds the link to the blocklist. The page then shows the first resource not on the blocklist. No lesson file changes. When both are blocked, the page says so, and lint fails the lesson until `fix-lesson` picks a new one.
