# Compile from a transcript

Intake only. It ends with a draft `course.md` and hands off to `compile.md`.

1. **Make the course dir.** Pick a short slug for the product, such as `corsego`. Create `<root>/<slug>/course/source/` and run `git init` in `<root>/<slug>`. Copy the transcript to `course/source/transcript.txt`.
2. **Split.** `byox split course/source/transcript.txt course/source/lectures`. The output is the lecture table: number, `text` or `empty`, title. Section headers (`=== ... ===`) are dropped because Udemy exports scramble them. Trust lecture order, not sections.
3. **Find the mentor's repo.** Search GitHub for the course title, the mentor's name and the product name. Fix names the speech-to-text garbled by ear. Look for a lecture titled "source code" or "useful links". If you find the repo, clone it to `course/source/upstream`.
4. **Match.** With a repo, run `byox match course/source/lectures course/source/upstream > course/source/map.tsv`. Read every row with a score below 0.30 yourself and fix the match by hand in the TSV. Without a repo, skip this step and mark every lesson `reconstructed: true`. Code truth then comes from speech.
5. **Classify every lecture.** Read the lectures in order, in chunks. Each one builds, is ops, or is noise. Noise is promos, environment fixes, editor tips and upgrade troubleshooting. Ops is deploy, production email, S3 and similar. Noise goes to `dropped:` with a reason. Ops lessons get `track: ops`.
6. **Group into lessons.** Group consecutive building lectures into lessons, one feature each. Split each lesson into steps, one commit-sized unit per step. Lesson 1 starts from an empty folder. Its first step runs the project generator with the mentor's flags.
7. **Inventory.** List every external service the source uses: payments, storage, OAuth, email. List the concepts each lesson teaches and pick one owner lesson per new concept.
8. **Write `course/course.md`** with `status: draft`, per `references/course-format.md`. Include the coverage table that maps every feature of the final product to step ids. Then open `compile.md` at step 1.
