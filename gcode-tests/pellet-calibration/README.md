# Pellet Calibration Suite (DYZE Pulsar Atom)

Bench G-code you run **straight from Duet Web Control (DWC)** to characterise a
**pellet material's flow behaviour** — the groundwork for dynamic flow-rate
control and the Pulsar Flow % used in the Grasshopper pipeline. Generic across
materials (PLA / PETG / ABS / ASA / PC / TPU / PA / PP / custom).

The workflow, in order:

1. **Max rate** — step extrusion speed up until the screw stalls (torques out).
2. **Min rate** — step down until flow becomes inconsistent.
3. **Dynamic flow calibration** — sweep speeds across that min–max window, weigh
   each purge, and build a *commanded speed → actual mass flow* map.

No robot / UR script, no slicer — only temperature and extrusion are driven, all
through DWC.

## What's here

```
gcode-tests/pellet-calibration/
├── README.md                        <- this file
├── MATERIAL_TEMPERATURES.md         <- starting temps/drying for common pellets
├── Standalone_Max_Flow_Test.g       <- optional all-in-one max-flow test (one file)
└── macros/                          <- clickable "step through the stages" panel for DWC
    ├── 00_Config.g                  <- pick material + edit numbers (shared by all stages)
    ├── 01_Heat_And_Soak.g           <- Stage 1: heat to temp + soak the barrel
    ├── 02_Prime.g                   <- Stage 2: fill the melt zone, confirm clean flow
    ├── 03_Flow_Ladder.g             <- Stage 3: find MAX rate (writes matMaxFeed)
    ├── 04_Cooldown.g                <- heaters off
    ├── 05_Jog_Extrude.g             <- utility: extrude at a constant speed you type in
    ├── 06_Min_Rate_Finder.g         <- find MIN rate (writes matMinFeed)
    └── 07_Dynamic_Flow_Calibration.g<- weigh-per-sample flow map (min→max)
```

## Quick start

1. Upload the `macros/` folder to `0:/macros/` (drag onto DWC's **Macros** file
   list, or copy via SFTP). Each `.g` becomes a button; a subfolder becomes a
   group — e.g. `0:/macros/Pellet-Calibration/`.
2. Open `00_Config.g` in DWC's editor, set `matName` to your material, save.
3. On the **Macros** page press, in order: **01** → **02** → **03** → **06** →
   **07**, then **04** to cool down. **05** is a free-form jog you can use anytime.

> Prefer one file for just the max test? Upload `Standalone_Max_Flow_Test.g` to
> `0:/gcodes/` and press **Start**.

## The DWC "debug UI" — clicking through the stages

No custom plugin needed. RepRapFirmware gives us two things:

1. **Macros are buttons.** Every `.g` under `0:/macros/` shows up on DWC's
   **Macros** page; subfolders become groups. So `macros/` *is* the step-through
   panel.
2. **Interactive dialogs.** `M291 ... S4 K{"A","B","C"}` pops a modal with choice
   buttons (result in `input`), and `M291 S5/S6` pops a **numeric-entry** box
   (result in `input`, with `L`/`H` bounds). That's how the ladders branch on
   your judgement and how the flow cal collects the weighed mass. (Keep choice
   dialogs to **≤ 3 buttons** — more than three reset the firmware on early RRF
   3.5.)

> A full custom DWC *plugin* (a Vue.js panel with sliders/live charts) is
> possible later, but macros + `M291` give you the step-through now.

## The tests

### Max rate — `03_Flow_Ladder.g`
Extrudes for `matStepSeconds` at a rising speed (`matLadderStart` → `matLadderMax`
in `+matLadderStep` rungs). After each rung it **stops and asks whether the screw
kept up**. On a reported stall it saves the previous rung to **`matMaxFeed`**.
*A stall looks/sounds like:* output thins or pulses, motor loads up audibly, or a
closed-loop drive throws a following-error.

### Min rate — `06_Min_Rate_Finder.g`
Starts from your established max and steps **down** until you report flow has gone
inconsistent (pulsing / gaps / dribble), saving the last good speed to
**`matMinFeed`**. Especially important for soft melts like TPU.

### Dynamic flow calibration — `07_Dynamic_Flow_Calibration.g`
Sweeps N speeds evenly from `matMinFeed` to `matMaxFeed`. For each: extrude for a
set time, **weigh the purge, type the grams**. It computes, per point, actual
**g/s**, **mm³/s** (if density is set), and **grams per mm of commanded E** (the
flow "gain"), and echoes CSV-style rows to the console. Screw extruders slip more
at high speed, so this curve is usually non-linear — that's the point of
measuring it.

### Constant-speed jog — `05_Jog_Extrude.g`
Type a speed and a run time; extrudes at exactly that speed as one continuous
move (no segmenting, so the screw holds a true constant speed) and loops for easy
re-runs. Handy for eyeballing flow around a threshold. Cancel the macro in DWC or
e-stop to end early.

## Using the flow data in Grasshopper (Pulsar Flow %)

Stage 7 prints lines like:

```
FLOWCAL_HDR, material, speed_mmpm, time_s, cmdE_mm, mass_g, g_per_s, mm3_per_s, g_per_mmE
FLOWCAL_ROW, PETG , 120 , 30 , 60 , 2.10 , 0.070 , 55.1 , 0.035
FLOWCAL_ROW, PETG , 360 , 30 , 180 , 6.05 , 0.202 , 158.9 , 0.0336
...
FLOWCAL_SUMMARY, mean g/mm_E = 0.0345 , spread across points = 8.2 % , g/s at max feed = 0.33
```

Copy the `FLOWCAL_ROW` lines out of the DWC console (Console page → they persist
in the log). Two ways to feed Grasshopper:

- **Linear (single Pulsar Flow %)** — if `spread` is small (≲10 %), the flow gain
  `g_per_mmE` is roughly constant, so one multiplier works. Set Pulsar Flow % so
  GH's assumed deposition matches the measured `g_per_mmE`:
  `Flow % = (GH_assumed_g_per_mmE / measured_g_per_mmE) × 100`.
  The measured mean is also saved to the global `matGramsPerEmm`.
- **Non-linear (flow map)** — if `spread` is large, feed the `speed → g_per_s`
  (or `speed → mm³_per_s`) pairs into a GH curve/remap so Flow % varies with
  commanded speed. This is the accurate route for a screw extruder.

`matMaxFlow` (g/s at max feed) is saved too — a useful hard cap for GH's speed
planning.

> Tell me how the Pulsar Flow % is actually consumed in the `.gh` definition
> (single multiplier vs. a lookup curve) and I can tailor the output format /
> add a small converter so it drops straight in.

## Units — important

No filament means RRF's **E axis is a calibration abstraction**: E feedrate is
mm/min of *commanded extrudate* per your `M92 E…` steps/mm. The mm numbers are
relative — the tests care about ratios, stall points, and the measured **mass**.
Optional live readouts in `00_Config.g`:

- `matEmmPerRev` — mm E per screw revolution → prints **screw RPM** per rung.
- `matMm3PerEmm` — mm³ per mm E → prints **mm³/s** per rung.

The Pulsar Atom screw tops out around **150 RPM / ~1000 g/h (≈234 mm³/s)** per
Dyze — if the ladder nears that without stalling, you're hardware-flow-limited,
not torque-limited.

## Temperatures

Per-material starting points and drying schedules live in
**[MATERIAL_TEMPERATURES.md](MATERIAL_TEMPERATURES.md)** and are baked into the
`00_Config.g` presets. Only the nozzle/lower zone is driven by default; the
middle/top zone heaters are **commented, clearly-marked lines** in
`01_Heat_And_Soak.g` because the heater→zone index depends on your `config.g`
(`M950`/`M563`). **Dry hygroscopic pellets** — moisture sputter reads as a false
stall.

## Safety

- Never extrude cold — the macros refuse below (target − 10 °C); keep `M302`
  cold-extrude protection enabled in `config.g`.
- The ladders and flow cal raise the E speed limit (`M203 E…`) so moves aren't
  silently clamped. **This persists until reboot or config reload** — re-run
  `config.g` (or reset) afterwards to restore your normal limit.
- Keep hands clear of the hot nozzle and have a tray ready for purge.

## Sources

- [DYZE Design — Pulsar™ Atom pellet extruder](https://dyzedesign.com/pulsar-atom-pellet-extruder/)
- [DYZE Design docs — Pulsar™ Atom](https://docs.dyzedesign.com/pulsar-atom.html)
- [RepRapFirmware `M291` message boxes / numeric & choice input (Duet3D)](https://docs.duet3d.com/User_manual/Reference/Gcode_meta_commands)
- Material temp/drying sources listed in [MATERIAL_TEMPERATURES.md](MATERIAL_TEMPERATURES.md).
