# Walkthrough Rendering Pipeline — Design Notes

Background and design rationale for the auto-generated GH definition walkthroughs. Read this before starting work on `tools/render_walkthrough.py` or the named-group convention.

## What we're trying to solve

Our 3DP script lives across several Grasshopper definitions. As we change them, the documentation drifts. Hand-written walkthroughs get stale within a release or two — nobody updates the screenshots, the prose stops matching the canvas, and new team members read docs that describe a definition that no longer exists.

We want a system where the canonical documentation of a `.gh` file is **regenerated automatically from the file itself** whenever it changes, with prose written by humans but image rendering handled by a script. Specifically:

- Every meaningful cluster of nodes in a `.gh` file gets its own image in the docs.
- The images are auto-rendered from the file — no manual screenshotting.
- Prose (what the cluster does, why it exists, gotchas) is written by humans and preserved across regenerations.
- Documentation lives in the repo alongside the code, so it's diffable and reviewable in PRs.

## Why not just take screenshots?

We considered three alternatives and discarded each:

1. **Manual screenshots.** Doesn't survive contact with development. Always stale.
2. **AI-driven UI automation (Cowork's computer use).** Possible in principle — Claude can drive Rhino's UI and screenshot — but slow, unreliable on dense UIs like the GH canvas, and macOS-only at the moment. The GH canvas is exactly the kind of visually dense UI where screen-driven agents struggle.
3. **A standalone GH file parser.** A `.gh` file is a binary serialisation of GH's component graph. Only Grasshopper itself knows how to deserialise and lay it out. There's no third-party "render a GH file from outside" tool, and there hasn't been one for years despite repeated forum requests.

## What we're doing instead

Use Grasshopper's **own canvas rendering API** via Rhino.Inside in headless mode. This is the same code path that File → Export Hi-Res Image uses internally, but driven from a Python script instead of the GUI. No screenshots, no UI automation — just programmatic rendering of the canvas to PNG.

The relevant API surface:

- `GH_Canvas.GenerateHiResImage(rect, settings, out totalSize)` — renders a given bounding rectangle of the canvas to a PNG, returns file paths.
- `GH_Canvas.GenerateHiResImageTile(viewport, bg)` — lower-level tile renderer if we need more control.
- `Rhino.RhinoApp.GetPlugInObject("Grasshopper")` — gets the GH plugin object, which exposes `RunHeadless(...)` for loading and solving definitions without the UI.

The orchestration is plain Python via `rhinoinside`:

```python
import rhinoinside
rhinoinside.load()
import Rhino
gh = Rhino.RhinoApp.GetPlugInObject("Grasshopper")
gh.RunHeadless()
# load file, enumerate groups, render each group's bbox to PNG
```

## The unit of documentation: GH Groups

Grasshopper has native **Groups** — coloured backdrops you can drop behind a cluster of components, with a name and colour. We use these as the structural unit of documentation. Each named group becomes one section in the walkthrough.

This is deliberate — it puts the documentation structure inside the GH file itself. When Louis adds a new cluster, he just gives the group a name and the next doc build picks it up automatically. No separate metadata to maintain, no JSON files mapping components to docs.

### Naming convention

```
NN — Title
```

- `NN`: two-digit prefix used for ordering in the output. `01`, `02`, `03`, etc.
- Em dash separator (` — `) for readability. A regular hyphen is fine if the em dash is annoying to type — be consistent within a file.
- `Title`: short description of what the cluster does.

Examples: `01 — Input`, `02 — Surface analysis`, `03 — Contour generation`, `04 — NP slicing`, `05 — Output`.

### Excluding scratch work

Any group whose name starts with `_` is **excluded** from the walkthrough. Use this for debug visualisations, scratch experiments, or anything you don't want documented. Examples: `_debug`, `_old contour logic`, `_TODO`.

### One responsibility per group

If a group is doing two things, split it into two groups. The walkthrough is only as clear as the grouping. This is also good practice for working in the canvas — it forces you to think about what each cluster's job actually is.

## What the render script does

`tools/render_walkthrough.py`, run as:

```
python tools/render_walkthrough.py path/to/definition.gh
```

Steps:

1. Load Rhino.Inside, start GH headless.
2. Open the `.gh` file.
3. Enumerate all GH Groups in the document.
4. Filter out underscore-prefixed groups.
5. Sort by the `NN` prefix.
6. For each remaining group:
   - Get its bounding rectangle on the canvas.
   - Pad the bbox slightly (so the group's title is included and the edges aren't clipped).
   - Render to PNG via `GH_Canvas.GenerateHiResImage`.
   - Background: white or transparent (transparent is nicer for dark-mode markdown viewers; pick one, document it).
   - Output to `docs/walkthroughs/<gh_filename>/img/NN_title.png`.
7. Generate or update `docs/walkthroughs/<gh_filename>/README.md`:
   - Each group becomes a section, `## NN — Title`.
   - Image embedded under the heading.
   - Prose section below.
   - **Critical:** preserve existing prose for groups that already have it. Only insert placeholder text for new groups.

## Output structure

```
docs/
└── walkthroughs/
    ├── slicer_main/
    │   ├── README.md
    │   └── img/
    │       ├── 01_input.png
    │       ├── 02_surface_analysis.png
    │       └── 03_contour_generation.png
    └── infill_demo/
        ├── README.md
        └── img/
            └── 01_input.png
```

## The hard bit: preserving prose across regenerations

When the script runs a second time, groups in the GH file may have been added, renamed, removed, or reordered. We need to update the markdown without losing the prose someone has already written. This is the most important detail to get right — without it, the pipeline becomes "regenerate and lose all docs," and people will stop running it.

Suggested approach (open to better ideas from whoever implements it):

- Use HTML comment markers in the markdown to delimit auto-generated sections vs. prose:

  ```markdown
  ## 01 — Input
  <!-- gh-walkthrough:image:01_input -->
  ![](img/01_input.png)
  <!-- /gh-walkthrough:image -->

  <!-- gh-walkthrough:prose:01_input -->
  This cluster takes the input BREP from Rhino and validates it has at least
  one closed surface before passing it downstream.
  <!-- /gh-walkthrough:prose -->
  ```

- On regeneration:
  - Parse the existing markdown, extract prose blocks keyed by group ID (use a slugified version of the title — `01_input`, not the full `01 — Input`).
  - Render new images.
  - Rebuild the markdown from a template, inserting prose blocks back in by key.
  - For groups that no longer exist: keep their prose at the bottom of the file under a `## Removed sections` heading so we don't silently lose it.
  - For groups that have been renamed: match by prefix number first, fall back to fuzzy title match, fall back to "removed" if neither.

This needs care. Worth writing tests for the merge logic specifically — give it a fake "before" markdown and "after" group list and check the right prose lands in the right place.

## Caveats and known issues

- **Rhino.Inside CPython is Windows-only.** On macOS the equivalent is launching `Rhino -runscript` pointing at a Python file. Pick one path and document it. No need to support both initially. Whichever the team's primary OS is wins.
- **Third-party plugins matter.** If a definition uses Kangaroo, Pufferfish, MetaHopper, etc., the headless Rhino instance needs them installed too — otherwise those components render as red error capsules in the output PNGs. Pin the list of required plugins in `CONTRIBUTING.md`.
- **First run is slow.** Loading Rhino + GH headless takes ~10–20 seconds even without the UI. Per-file rendering after that is fast (sub-second per group). Fine for a doc build that runs on merge or on demand. Not fine for instant feedback during editing.
- **Large groups may need stitching.** `GenerateHiResImage` handles tiling internally and returns multiple files for huge regions. The script should detect this and either stitch them with PIL or accept multiple images per group.
- **Group bounding box vs. visual bounds.** GH's group bbox includes the title bar but may or may not include component nicknames that float above/below components. Test this and pad the bbox appropriately so nothing gets clipped.
- **Plugin fallback: MetaHopper's `Capture GH Canvas` component** does similar work from inside a definition. If the headless Rhino.Inside route turns out to be too painful, we can fall back to having a "render docs" GH file that uses MetaHopper to capture each definition's canvas. Less programmable but easier to set up. Don't go this route unless the headless approach genuinely doesn't work — having the doc generation be a normal Python script is much cleaner.

## How this fits with the broader docs workflow

Once `render_walkthrough.py` works:

- It runs locally when someone wants to regenerate docs after editing a `.gh` file.
- Eventually it could run via GitHub Actions on every PR that touches a `.gh` file, with the bot opening a follow-up PR with regenerated docs. Worth doing only after the script is stable — premature automation will be more annoying than useful.
- The doc PRs go through the same review process as everything else (see `CONTRIBUTING.md`).
- For prose updates that aren't tied to a `.gh` change, just edit the markdown directly. The next regeneration will preserve your changes via the prose markers.

## What's done when

Repeating from `TASKS.md` for clarity:

- Naming convention is documented in `CONTRIBUTING.md`.
- Running `python tools/render_walkthrough.py path/to/definition.gh` produces a PNG-per-group output and an updated markdown file.
- The script handles added/renamed/removed groups without nuking existing prose.
- At least one existing GH file in the repo has been retro-fitted with named groups and run through the pipeline as the reference example.

## Questions still open

- Windows or Mac as the primary target? (Affects Rhino.Inside vs. `Rhino -runscript`.)
- White, transparent, or matched-to-canvas background for the PNGs?
- Should we render a full overview image of each `.gh` file at the top of its README too, in addition to per-group images? Probably yes — gives readers a map before they dive in.
- How do we want to handle clusters that are conceptually one thing but visually span across the canvas? (Probably: don't. If it's one logical step, it should be one group, even if that means rearranging the canvas. Forces good hygiene.)
