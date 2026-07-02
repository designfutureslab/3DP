# Pellet material temperature guide

Starting-point temperatures for common **pellet** materials on the DYZE Pulsar
Atom (3-zone screw extruder). These match the presets in `macros/00_Config.g` —
pick your material there (`matName`) and it loads the row below.

> ⚠️ **These are starting points, not gospel.** Pellet feedstock varies a lot by
> grade, filler, and colour, and the right number depends on your screw, nozzle
> size, and flow rate. **Because a pellet extruder's melt zone is long, residence
> time is high, so it usually runs a little COOLER than the equivalent filament**
> — start at these numbers and tune down first. Always run the max-flow ladder
> (Stage 3) at your chosen temperature; if it stalls early, a small temperature
> bump often buys more flow.

## Zone layout (Pulsar Atom)

Three heated zones along the barrel: **top / feed** (cold pellets enter here),
**middle** (stabilises the melt), **nozzle / lower** (final, even flow). A good
default is to run all three **flat** (same temperature), then, per Dyze's
guidance, **drop the top/feed zone in ~10 °C steps** if pellets bridge or the
screw whines/jams at the throat. Only the nozzle/lower zone is driven by default
in `01_Heat_And_Soak.g`; wire the other two to your board's heater indices (the
commented lines in that macro).

## Temperatures

All °C. "Nozzle" = nozzle/lower zone active temp. Bed is a first-layer starting
value. Density is used by the flow calibration (Stage 7) to convert mass → mm³.

| Material | Nozzle | Middle | Top/feed | Bed | Density (g/cm³) | Hygroscopic? |
|----------|:------:|:------:|:--------:|:---:|:---------------:|:------------:|
| **PLA**  | 200    | 195    | 185      | 55  | 1.24 | Mild |
| **PETG** | 235    | 235    | 230      | 80  | 1.27 | Yes |
| **ABS**  | 245    | 240    | 230      | 100 | 1.04 | Mild |
| **ASA**  | 250    | 245    | 235      | 100 | 1.07 | Mild |
| **PC**   | 275    | 270    | 255      | 110 | 1.20 | High |
| **TPU**  | 225    | 220    | 210      | 50  | 1.21 | High |
| **PA** (nylon) | 255 | 250 | 240   | 85  | 1.14 | Very high |
| **PP**   | 230    | 225    | 215      | 90  | 0.91 | None |

## Drying (do this first for anything hygroscopic)

Moisture is the #1 cause of sputtering, foaming, and steam bubbles — which read
as a false stall in the max-flow test. Dry the **pellets** before loading.

| Material | Dry temp | Dry time | Notes |
|----------|:--------:|:--------:|-------|
| PLA  | 45 °C  | 4–6 h  | Keep below ~50 °C so pellets don't tack together |
| PETG | 65 °C  | 4–6 h  | Dries easily; store with desiccant |
| ABS  | 70 °C  | 2–4 h  | |
| ASA  | 70 °C  | 2–4 h  | |
| PC   | ~90 °C | 4–8 h  | Very hygroscopic; dry hot |
| TPU  | 55 °C  | 4–8 h  | Low temp, long time; tacky if too hot |
| PA (nylon) | 90 °C | 8–12 h | Extremely hygroscopic; dry immediately before use |
| PP   | (none) | —      | Absorbs <0.01%; a 70 °C pre-heat only helps if condensation is present |

## Per-material notes

- **PLA** — easiest; watch heat creep at the feed throat, keep the top zone cool.
- **PETG** — stringy; strong layer bonding. Long melt zone tolerates the lower
  end of the range well.
- **ABS / ASA** — need an enclosure and a hot bed or they warp; ASA handles UV
  better outdoors.
- **PC** — hot and stiff; needs a heated chamber for big parts. Dry aggressively.
- **TPU** — flexible; the *minimum* flow rate matters more here (soft melt is
  prone to inconsistent low-speed flow), so Stage 6 is especially useful.
- **PA / nylon** — strong and abrasive (use a hardened nozzle); moisture is
  brutal, dry right up to printing.
- **PP** — low density, warps hard, bonds to almost nothing except PP tape;
  barely absorbs moisture.

## Sources

- [DYZE Design — Pulsar™ Atom (3-zone barrel, lower temps for long melt zone)](https://dyzedesign.com/pulsar-atom-pellet-extruder/)
- [Filament / pellet nozzle temperature ranges (Sovol materials guide)](https://www.sovol3d.com/blogs/news/3d-print-nozzle-temperature-guide-for-materials-2026)
- [Drying temperatures for filament, flake, and pellets (re:3D)](https://re3d.zendesk.com/hc/en-us/articles/360038462411-Drying-Filament-Flake-and-Pellets)
- [Polymaker Wiki — PP (moisture insensitivity)](https://wiki.polymaker.com/the-basics/3d-printing-materials/pp)
