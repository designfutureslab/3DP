# Contributing

Conventions for working in this repo. Three-person team — keep it light, but consistent.

## Branching

- `main` is always working. Don't push to it directly.
- Branch off `main` for every task. Naming: `feature/<short-name>`, `fix/<short-name>`, `cleanup/<short-name>`. Lowercase, hyphenated, short — e.g. `feature/per-segment-speed`, `fix/brep-multi-surface`.
- One feature per branch. If a task grows, split it.

## Commits

- Imperative mood, present tense: "Add per-segment speed control", not "Added" or "Adds".
- First line ≤ 72 chars. If you need more detail, blank line then a short body explaining *why*.
- Commit often locally, but tidy up before pushing — squash trivial "fix typo" / "wip" commits into the meaningful one with `git rebase -i`.
- Don't commit generated G-code, large test STLs, slicer output, or anything in `__pycache__/`. Add to `.gitignore` if it keeps showing up.

## Pull requests

- One PR per branch, against `main`.
- PR title = what the change does, in plain English.
- PR description should cover: **what** changed, **why**, and **how to test it** (input geometry + expected behaviour). A screenshot or short clip of the toolpath preview is great for anything visual.
- Link the relevant issue with `Closes #N` so it auto-closes on merge.
- Keep PRs small where possible. A 200-line PR gets reviewed properly; a 2,000-line one gets rubber-stamped or sits for a week.
- Don't merge your own PR without a review unless it's trivial (typos, comments, formatting-only).

## Reviews

- Address every comment before merging — either change the code, or reply explaining why not.
- "Resolve conversation" is the author's job, not the reviewer's.
- Use **Squash and merge** by default so `main` stays a clean linear history.

## Issues

- Use issues for bugs and feature requests that aren't already tracked.
- Bug template: what you did, what happened, what you expected, geometry/file used, error message or screenshot.
- Tag with labels (`bug`, `enhancement`, `non-planar`, `infill`, etc.) so things are filterable later.

## Things to avoid

- Force-pushing to `main` or to anyone else's branch.
- Committing API keys, machine IPs, or anything machine-specific. Use a config file that's gitignored.
- Mixing unrelated changes in one PR ("while I was in there I also fixed…"). Split it.
- Long-lived feature branches. If a branch is more than ~2 weeks old, rebase onto `main` and merge what's ready, or split it.
