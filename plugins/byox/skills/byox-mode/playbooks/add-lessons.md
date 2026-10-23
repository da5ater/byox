# Add lessons to a course

The learner already has a compiled course and wants more lessons in it. The source may be more of the same transcript, a new chapter, a repo's later commits, a new article, or just a feature they name. `B` is the absolute path of `scripts/byox` next to `SKILL.md`. `C` is the course dir. The site's "Add lessons" button runs this headless, and the learner can ask for it in chat.

The course stays usable the whole time. New lessons are marked `building: true` until they are done, and the site holds them back.

1. **Read the course.** Read `C/course/course.md` in full: the outline, the stack, the services, the concepts and the coverage table. Read the last lesson file to match its style. Find what the request names. Without a source, ask the learner, or when headless, stop and say what you need.
2. **Find the new material.** For a transcript, run `B split` on the new part and `B match` against the mentor's repo, as in `compile-transcript.md` steps 2 to 5. For a repo, `compile-repo.md` step 1 with the next cutoff. For an article, `compile-article.md`. Keep the course's original ordering: new lessons go after the last existing one unless the learner says otherwise.
3. **Group it into new lessons.** One feature per lesson, one commit-sized unit per step, as in `compile-transcript.md` step 6. Number from the next free number. Step ids start with the lesson number.
4. **Extend the outline.** Append the new lessons to `lessons:` in `course.md` with `building: true`. Add their concepts, their coverage rows and any dropped lectures. Keep `status: compiled`. Ask nothing the course already answers: the stack and test framework are already in `stack:`. A new paid service is the one thing to ask about.
5. **Scaffold.** `B new C`. It is safe to rerun and never overwrites an existing lesson. It adds stubs for the new ones.
6. **Write and review, two agents per lesson.** Follow `compile.md` steps 4 to 9 for the new lessons only, one `lesson-writer` and then one independent `lesson-reviewer` each, in lesson order. Existing lessons and their solution tags stay as they are. The first new step starts from the course's last tag.
7. **Release.** When a lesson's writer and reviewer are both done and `B lint C --lesson <id>` and `B strength C --lesson <id>` are clean, remove `building: true` from that lesson in `course.md`. Release them in order. A lesson that is blocked keeps `building: true`, and so do all after it.
8. **Report.** Which lessons were added and released, which are still building and why, and anything the learner must decide. Run `B sync`.
