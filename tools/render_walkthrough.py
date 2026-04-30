"""
render_walkthrough.py — auto-render GH definition walkthroughs

Enumerates named GH Groups in a .gh file, renders each to a PNG via
Grasshopper's canvas API, and generates/updates a markdown walkthrough
under docs/walkthroughs/<definition_name>/README.md.

Prose written inside the gh-walkthrough:prose markers is preserved
across re-runs. Groups removed from the definition are moved to a
## Removed sections block rather than silently dropped.

─────────────────────────────────────────────────────────────────────
MAC USAGE (IronPython inside Rhino — current target)
─────────────────────────────────────────────────────────────────────
Pass the .gh path as an argument to RunPythonScript, e.g. via Terminal:

    /Applications/Rhino\ 8.app/Contents/MacOS/Rhino \
        -runscript "RunPythonScript('tools/render_walkthrough.py','path/to/def.gh')"

Or open Tools → PythonScript → Edit in Rhino, set GH_FILE at the top
of the file, and hit Run.

─────────────────────────────────────────────────────────────────────
WINDOWS USAGE (Rhino.Inside CPython — not yet implemented)
─────────────────────────────────────────────────────────────────────
See issue #5 for the Windows port. The same core logic will be reused;
only the bootstrap block at the bottom changes.

─────────────────────────────────────────────────────────────────────
NAMING CONVENTION (required for this script to pick up your groups)
─────────────────────────────────────────────────────────────────────
Groups must be named:  NN — Title
  e.g.  01 — Input,  02 — Surface analysis,  03 — Contour generation

Groups whose name starts with _ are excluded (use for debug/scratch).
One logical responsibility per group — split if a group does two things.
"""

import sys
import os
import re


# ─── Argument handling ────────────────────────────────────────────────────────

def resolve_gh_path():
    """
    Accept the .gh path from:
      1. sys.argv[1]  — when invoked via RunPythonScript('script.py','path.gh')
      2. GH_FILE env var — useful during development
    Raises ValueError if neither is set.
    """
    if len(sys.argv) > 1 and sys.argv[1].endswith('.gh'):
        return os.path.abspath(sys.argv[1])
    env = os.environ.get('GH_FILE', '').strip()
    if env:
        return os.path.abspath(env)
    raise ValueError(
        "No .gh file specified.\n"
        "Pass it as an argument: RunPythonScript('render_walkthrough.py', 'path/to/def.gh')\n"
        "or set the GH_FILE environment variable."
    )


# ─── GH document loading ─────────────────────────────────────────────────────

def load_document(gh_path):
    """Open a .gh file and return the GH_Document. Raises on failure."""
    import Grasshopper.Kernel as ghk
    io = ghk.GH_DocumentIO()
    if not io.Open(gh_path):
        raise IOError("Grasshopper could not open: {}".format(gh_path))
    return io.Document


# ─── Group enumeration ───────────────────────────────────────────────────────

GROUP_PREFIX_RE = re.compile(r'^(\d+)')

def sorted_groups(doc):
    """
    Return GH_Group objects whose names match 'NN — Title', excluding
    any whose name starts with _.  Sorted by the leading NN number.
    """
    from Grasshopper.Kernel.Special import GH_Group

    groups = []
    for obj in doc.Objects:
        if not isinstance(obj, GH_Group):
            continue
        name = (obj.NickName or '').strip()
        if not name or name.startswith('_'):
            continue
        groups.append(obj)

    def sort_key(g):
        m = GROUP_PREFIX_RE.match(g.NickName or '')
        return int(m.group(1)) if m else 9999

    return sorted(groups, key=sort_key)


def slug(name):
    """
    'NN — Title' -> 'nn_title'  (used as image filename and prose key)
    Keeps only word chars, lowercased, with _ separators.
    """
    s = re.sub(r'\s*[—–-]+\s*', '_', name)
    s = re.sub(r'[^\w]+', '_', s)
    return s.strip('_').lower()


# ─── Canvas rendering ────────────────────────────────────────────────────────

RENDER_PADDING = 40.0   # canvas units; keeps group title bar from being clipped
RENDER_ZOOM    = 1.0    # 1:1 — increase for higher DPI output


def make_canvas(doc):
    """
    Instantiate a GH_Canvas, attach the document, and run a solution
    so component states are correct before we try to read bounds.

    NOTE: GH_Canvas is a UI control. On Mac it is an Eto.Forms control;
    on Windows it is a WinForms control. We instantiate it without a
    parent — it won't be shown, but the API surface we need (group bounds
    + GenerateHiResImage) does not require it to be visible.
    """
    from Grasshopper.GUI.Canvas import GH_Canvas
    canvas = GH_Canvas()
    canvas.Document = doc
    doc.NewSolution(True)   # solve so bounds are computed
    return canvas


def render_group_to_png(canvas, group, out_path):
    """
    Render a single group's bounding region to a PNG at out_path.
    Transparent background.

    GenerateHiResImage may return multiple tile paths for very large groups;
    we handle the common single-tile case and warn on multi-tile so we know
    to implement stitching when we first hit it.
    """
    import System
    import System.IO as sio
    from Grasshopper.GUI.Canvas import GH_Canvas

    bounds = group.Attributes.Bounds       # System.Drawing.RectangleF
    padded = System.Drawing.RectangleF(
        bounds.X      - RENDER_PADDING,
        bounds.Y      - RENDER_PADDING,
        bounds.Width  + RENDER_PADDING * 2,
        bounds.Height + RENDER_PADDING * 2,
    )

    settings = GH_Canvas.GH_HiResImageSettings()
    settings.Zoom = RENDER_ZOOM
    # Transparent background — nicer in dark-mode markdown viewers.
    # If you prefer white: settings.Background = System.Drawing.Color.White
    settings.Background = System.Drawing.Color.Transparent

    tiles = canvas.GenerateHiResImage(padded, settings)

    if tiles is None or len(tiles) == 0:
        raise RuntimeError(
            "GenerateHiResImage returned no output for group '{}'".format(group.NickName)
        )

    if len(tiles) == 1:
        sio.File.Copy(tiles[0], out_path, True)
    else:
        # Multi-tile: copy each with a numeric suffix and warn.
        # TODO: stitch tiles with System.Drawing.Bitmap when we need it.
        base, ext = os.path.splitext(out_path)
        for i, tile in enumerate(tiles):
            dest = "{}_{:02d}{}".format(base, i, ext)
            sio.File.Copy(tile, dest, True)
        print("  [warn] {} rendered as {} tiles — stitching not yet implemented.".format(
            group.NickName, len(tiles)
        ))


# ─── Markdown generation and prose preservation ───────────────────────────────

_PROSE_OPEN  = '<!-- gh-walkthrough:prose:{slug} -->'
_PROSE_CLOSE = '<!-- /gh-walkthrough:prose -->'
_IMAGE_OPEN  = '<!-- gh-walkthrough:image:{slug} -->'
_IMAGE_CLOSE = '<!-- /gh-walkthrough:image -->'
_PROSE_RE    = re.compile(
    r'<!-- gh-walkthrough:prose:([^\s>]+) -->(.*?)<!-- /gh-walkthrough:prose -->',
    re.DOTALL,
)
_REMOVED_RE  = re.compile(r'(## Removed sections.*)', re.DOTALL)

_PROSE_PLACEHOLDER = (
    '_Describe what this cluster does, why it exists, and any gotchas._'
)


def parse_prose(content):
    """Return {slug: prose_text} for all prose blocks in existing markdown."""
    return {
        m.group(1).strip(): m.group(2).strip()
        for m in _PROSE_RE.finditer(content)
    }


def parse_removed_block(content):
    """Return the existing ## Removed sections block, or None."""
    m = _REMOVED_RE.search(content)
    return m.group(1) if m else None


def build_section(group_name, group_slug, img_rel, prose_text):
    return '\n'.join([
        '## {}'.format(group_name),
        '',
        _IMAGE_OPEN.format(slug=group_slug),
        '![]({})'.format(img_rel),
        _IMAGE_CLOSE,
        '',
        _PROSE_OPEN.format(slug=group_slug),
        prose_text,
        _PROSE_CLOSE,
        '',
    ])


def build_readme(definition_name, groups_and_slugs, existing_prose, removed_block):
    parts = [
        '# {} — Walkthrough'.format(definition_name),
        '',
        (
            '_Auto-generated by `tools/render_walkthrough.py`. '
            'Edit prose between `gh-walkthrough:prose` markers — '
            'those blocks are preserved on re-runs. '
            'Image sections are overwritten each time._'
        ),
        '',
    ]

    for group, group_slug in groups_and_slugs:
        prose = existing_prose.get(group_slug, _PROSE_PLACEHOLDER)
        img_rel = 'img/{}.png'.format(group_slug)
        parts.append(build_section(group.NickName, group_slug, img_rel, prose))

    if removed_block:
        parts.append(removed_block)

    return '\n'.join(parts)


def collect_stale_prose(existing_prose, current_slugs):
    """
    Return prose for slugs no longer present in the definition,
    skipping placeholder text (nothing meaningful to preserve).
    """
    return {
        k: v for k, v in existing_prose.items()
        if k not in current_slugs and v.strip() != _PROSE_PLACEHOLDER
    }


def append_stale_to_removed(stale, removed_block):
    """Append stale prose entries to the ## Removed sections block."""
    if not stale:
        return removed_block

    if removed_block is None:
        removed_block = '\n'.join([
            '## Removed sections',
            '',
            '_Prose from groups no longer in the definition. '
            'Review and delete once no longer needed._',
            '',
        ])

    for s, prose in stale.items():
        removed_block += '\n'.join([
            '',
            '### (removed) {}'.format(s),
            '',
            _PROSE_OPEN.format(slug=s),
            prose,
            _PROSE_CLOSE,
            '',
        ])

    return removed_block


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    # ── Resolve paths ──────────────────────────────────────────────────────
    try:
        gh_path = resolve_gh_path()
    except ValueError as e:
        print("Error: {}".format(e))
        sys.exit(1)

    if not os.path.isfile(gh_path):
        print("Error: file not found — {}".format(gh_path))
        sys.exit(1)

    definition_name = os.path.splitext(os.path.basename(gh_path))[0]

    # Script lives in tools/; repo root is one level up.
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir   = os.path.join(repo_root, 'docs', 'walkthroughs', definition_name)
    img_dir   = os.path.join(out_dir, 'img')
    readme    = os.path.join(out_dir, 'README.md')

    if not os.path.exists(img_dir):
        os.makedirs(img_dir)

    # ── Load document ──────────────────────────────────────────────────────
    print("Loading {}...".format(gh_path))
    doc = load_document(gh_path)

    # ── Enumerate groups ───────────────────────────────────────────────────
    groups = sorted_groups(doc)
    if not groups:
        print("No renderable groups found. "
              "Add named groups ('NN — Title') to your definition.")
        return

    print("Found {} group(s):".format(len(groups)))
    for g in groups:
        print("  {}".format(g.NickName))

    slugs = [slug(g.NickName) for g in groups]

    # ── Set up canvas ──────────────────────────────────────────────────────
    print("Initialising canvas...")
    canvas = make_canvas(doc)

    # ── Render each group ──────────────────────────────────────────────────
    for group, group_slug in zip(groups, slugs):
        out_png = os.path.join(img_dir, '{}.png'.format(group_slug))
        print("  Rendering '{}' -> img/{}.png".format(group.NickName, group_slug))
        render_group_to_png(canvas, group, out_png)

    # ── Load existing markdown and extract prose ───────────────────────────
    existing_prose = {}
    removed_block  = None

    if os.path.isfile(readme):
        with open(readme, 'r') as fh:
            old_content = fh.read()
        existing_prose = parse_prose(old_content)
        removed_block  = parse_removed_block(old_content)

        stale = collect_stale_prose(existing_prose, set(slugs))
        if stale:
            print("  [info] {} group(s) removed from definition; "
                  "prose moved to ## Removed sections.".format(len(stale)))
        removed_block = append_stale_to_removed(stale, removed_block)

    # ── Write README ───────────────────────────────────────────────────────
    content = build_readme(
        definition_name,
        list(zip(groups, slugs)),
        existing_prose,
        removed_block,
    )
    with open(readme, 'w') as fh:
        fh.write(content)

    print("Done. Walkthrough written to:\n  {}".format(out_dir))


main()
