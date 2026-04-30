# DFL 3DP Script — Improvement Tasks

This is the master tracking list. Each item below should become its own GitHub issue, and this list links to them with `- [ ] #N` once they exist.

> **How to set this up in GitHub**
> 1. Create one issue per task below (copy the heading + body into the issue).
> 2. Open a new issue titled "Tracking: 3DP script improvements" and paste this file's contents into it.
> 3. Replace each `- [ ]` line below with `- [ ] #12` (or whatever issue number GitHub assigns). GitHub will render checkboxes and auto-update progress as issues close.
> 4. Optional: tag a milestone (e.g. "v1 — refactor") and assign labels (`non-planar`, `infill`, `cleanup`, `enhancement`, `docs`).

---

## Suggested order

Open to changing this — it's my read on what unblocks what.

### Phase 1 — Foundations
- [ ] Script cleanup and formatting
- [ ] Robust BREP support with multiple surfaces
- [ ] Workflow for BREP and contour input (contour input not requiring BREP)
- [ ] Orientation normality adjustment
- [ ] Walkthrough rendering pipeline + named-group convention

### Phase 2 — Slicing logic
- [ ] Per-segment extrusion speed for non-planar contouring
- [ ] More robust / simpler retraction and leads for complex BREPs
- [ ] Simplify contouring strategies so weaves/spirals take different paths

### Phase 3 — Setup & output
- [ ] Improved print positioning (conformal-aware, multi-BREP)
- [ ] Bambu A1 scale print test output

### Phase 4 — Demos
- [ ] Basic non-planar slicing demonstration script
- [ ] Basic infill slicing demonstration script

---

## Task details

Copy each section below into its own GitHub issue.

---

### Script cleanup and formatting

Consistent naming, remove dead code, group related functions, add docstrings/comments at the function level. Run a formatter pass at the end. Where logic is non-obvious (especially around the NP math), leave a short comment explaining *why*, not just what.

**Done when:** code passes a formatter cleanly, no dead code, every public function has a docstring.

---

### Robust BREP support with multiple surfaces

Current handling falls over on multi-surface BREPs. Walk all faces, respect surface boundaries, produce a clean unified contour set per layer.

**Test cases:** single open surface, closed solid, multi-face BREP with internal seams.

**Done when:** all three test cases produce contiguous, correctly-ordered contours with no duplicate or dropped segments.

---

### Workflow for BREP and contour input (contour input not requiring BREP)

Refactor the input stage so contours can be fed in directly (e.g. from upstream Grasshopper logic or hand-authored curves) without needing to wrap them in a BREP first. BREP path must still work; contour path is the new addition.

**Done when:** the same downstream slicer accepts either a BREP or a list of contours and produces equivalent output where geometry overlaps.

---

### Orientation normality adjustment

Add a step that checks/flips contour normals to a consistent reference (build direction or surface outward) so extrusion direction and offsets behave predictably across imported geometry.

**Done when:** a deliberately mis-oriented input produces the same toolpath as a correctly-oriented one.

---

### Walkthrough rendering pipeline + named-group convention

Set up an automated pipeline that renders cluster-by-cluster images of each `.gh` file in the repo and assembles them into markdown walkthroughs under `docs/walkthroughs/`. Documentation should update automatically as the GH definitions change.

**Two parts:**

**1. Naming convention (do this first, costs nothing).**
Every `.gh` file in the repo should organise its logic into named GH Groups (the coloured backdrops). Group names are the unit of documentation. Convention:

- `NN — Title` where `NN` is a two-digit ordering prefix and `Title` is a short description. e.g. `01 — Input`, `02 — Surface analysis`, `03 — Contour generation`.
- One responsibility per group. If a group is doing two things, split it.
- Any group whose name starts with `_` (underscore) is excluded from the walkthrough — use this for scratch / debug clusters you don't want documented.

**2. Render script (`tools/render_walkthrough.py`).**
A Python script using Rhino.Inside (headless) that:
- Takes a `.gh` file path as input.
- Loads the file via `rhinoinside` and the Grasshopper plugin object's headless mode.
- Enumerates all GH Groups in the document, filters out underscore-prefixed ones, sorts by name prefix.
- For each group, gets its bounding rectangle and calls `GH_Canvas.GenerateHiResImage` with that rect to produce a PNG. White or transparent background.
- Writes PNGs to `docs/walkthroughs/<gh_filename>/img/NN_title.png`.
- Generates or updates `docs/walkthroughs/<gh_filename>/README.md` with each group as a section, image embedded, and a placeholder for prose if the section is new. Existing prose in already-documented sections is preserved.

**Done when:**
- Convention is documented in `CONTRIBUTING.md`.
- Running `python tools/render_walkthrough.py path/to/definition.gh` produces a PNG-per-group output and an updated markdown file.
- The script handles the case where groups have been added, renamed, or removed between runs without nuking existing prose.
- At least one existing GH file in the repo has been retro-fitted with named groups and run through the pipeline as the reference example.

**Notes:**
- Rhino.Inside CPython is Windows-only and needs Rhino installed locally; on macOS, equivalent is running the script via `Rhino -runscript`. Pick one path and document it — no need to support both initially.
- Any third-party GH plugins used in the definitions need to be installed in the same Rhino instance, or those components will render as red error capsules. Pin the list of required plugins in `CONTRIBUTING.md`.
- MetaHopper's `Capture GH Canvas` component does similar work from inside GH if the headless route turns out to be too painful — fall back to that if needed.

---

### Per-segment extrusion speed for non-planar contouring

Speed currently applies per layer/contour. Make it settable per segment so we can slow on overhangs, steep Z-deltas, or tight curvature without dropping the whole contour speed.

**Done when:** segment-level speed override is exposed in the slicer config and visible in the toolpath preview.

---

### More robust / simpler retraction and leads for complex BREPs

Lead-in/lead-out and retraction logic breaks on geometry with sharp internal transitions or multiple disconnected regions per layer.

**Done when:** lead placement is predictable, retraction never happens inside a visible surface, and travel moves between disconnected regions are safe (above the part).

---

### Simplify contouring strategies so weaves/spirals take different paths

Right now every strategy tries to be compatible with every input. Split them — weave, spiral, and standard contour each get their own path generation. It's fine if a strategy only supports a subset of inputs.

**Done when:** the three strategies are independent modules, and the README documents which inputs each one accepts.

---

### Improved print positioning (conformal-aware, multi-BREP)

Multiple BREPs / contour sets need to keep their *relative* positions on the build plate so a conformal print across several parts lines up.

**Supports:** single shared origin across all inputs, per-part offset overrides, preview of placed parts before slicing.

**Done when:** loading three offset BREPs produces a single G-code file with all three in correct relative position.

---

### Bambu A1 scale print test output

Output mode that scales the toolpath to fit the Bambu A1 build volume so we can do quick desktop-scale validation prints before committing to a full-size run on the robot.

**Done when:** a flag in the slicer config produces A1-scaled G-code that prints successfully on the A1.

---

### Basic non-planar slicing demonstration script

Standalone, minimal example showing the NP slicing pipeline end-to-end on a simple test geometry. Onboarding/teaching, not production.

**Done when:** a new user can clone the repo, run the demo script, and see a complete NP toolpath on the included test geometry with no extra setup.

---

### Basic infill slicing demonstration script

Same as above for infill — minimal standalone example.

**Done when:** demo runs on included test geometry and produces a viewable infill toolpath.
