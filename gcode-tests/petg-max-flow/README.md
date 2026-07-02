# PETG Pellet — Maximum Extrusion Rate Test (DYZE Pulsar Atom)

Bench G-code you run **straight from Duet Web Control (DWC)** to find the
maximum extrusion rate for a PETG pellet — the point where the screw motor can
no longer push melt fast enough and "torques out" (stalls / skips / thins the
output). This is step one toward dynamic flow-rate control: once you know the
ceiling, you can set flow targets and speed limits with a real margin.

No UR / robot-side script, no slicer — only temperature and extrusion are
driven, all through DWC.

## What's here

```
gcode-tests/petg-max-flow/
├── README.md                 <- this file
├── PETG_Max_Flow_Test.g      <- all-in-one: run one file start to finish
└── macros/                   <- clickable "step through the stages" version for DWC
    ├── 00_Config.g           <- edit your numbers here (shared by all stages)
    ├── 01_Heat_And_Soak.g    <- Stage 1: heat to PETG temp + soak the barrel
    ├── 02_Prime.g            <- Stage 2: fill the melt zone, confirm clean flow
    ├── 03_Flow_Ladder.g      <- Stage 3: the actual max-flow ladder test
    └── 04_Cooldown.g         <- Stage 4: heaters off
```

## The DWC "debug UI" — clicking through the stages

You asked whether we can add a bit of debugging UI in DWC to step through the
process. We don't need a custom plugin — RepRapFirmware gives us two things:

1. **Macros are buttons.** Every `.g` file under `0:/macros/` shows up as a
   clickable button on DWC's **Macros** page; subfolders become groups. So the
   `macros/` folder above *is* the step-through panel — press `01`, then `02`,
   then `03`, then `04`.
2. **Interactive dialogs.** `M291 ... S4 K{"A","B","C"}` pops a modal in DWC
   with choice buttons; the click comes back in the `input` variable so a
   running macro can branch. That's how the ladder asks "Good — go faster /
   STALLED — stop / Abort" after each rung. (Keep it to **≤ 3 buttons** — more
   than three caused a firmware reset on early RRF 3.5 builds.)

> A full custom DWC *plugin* (a Vue.js panel with your own controls) is also
> possible if you later want sliders/live charts, but it's a much bigger lift.
> Macros + `M291` get you the step-through UI now.

### Install (DWC)

Upload the whole `macros/` folder to `0:/macros/` (drag it onto DWC's
**System / Macros** file list, or copy via SFTP). Then on the **Macros** page
you'll see the numbered buttons. Edit `00_Config.g` from DWC's file editor to
set your temps and ladder.

Prefer one file? Upload `PETG_Max_Flow_Test.g` to `0:/gcodes/` and press
**Start**, or drop it in `0:/macros/` for a one-press button.

## How the test works

1. **Heat & soak** — reach the PETG target, then dwell so the *whole* melt zone
   (not just the sensor) is stable. Pellet extruders have a long barrel and need
   a real soak.
2. **Prime** — extrude until flow is clean and steady, so the ladder starts from
   a full, air-free melt zone (otherwise the first rungs read as false stalls).
3. **Flow ladder** — extrude for a fixed time at `ladderStart`, then step up by
   `ladderStep` each rung to `ladderMax`. After each rung it **stops and asks you
   whether the screw kept up.** When you report a stall, it records the previous
   rung as `petgMaxGoodFeed` (your usable maximum) and reports it.
4. **Cool down** — small relief retraction, heaters off.

**What a stall looks / sounds like:** output thins or pulses instead of a steady
rod, the motor audibly loads up, and on a closed-loop/servo screw drive you may
get a following-error. That rung is the ceiling; the rung below it is usable max.

## Units — important

There is no filament in a screw pellet extruder, so RRF's **E axis is a
calibration abstraction**: E feedrate is in mm/min of *commanded extrudate* per
your `M92 E…` steps/mm. The absolute mm numbers are **starting guesses** — the
value of the test is the *relative ladder* and where it stalls. Tune the numbers
to your machine.

If you know your calibration you can get real-world readouts printed at each
rung by setting in `00_Config.g` (or the vars at the top of the single file):

- `petgEmmPerRev` — mm of E per screw revolution → prints **screw RPM** per rung.
- `petgMm3PerEmm` — mm³ of melt per mm of E → prints **mm³/s** per rung.

Leave them at `0` to skip. The Pulsar Atom screw tops out around **150 RPM /
~1000 g/h (≈234 mm³/s)** per Dyze — if your ladder gets near that without
stalling, you're flow-limited by the hardware, not torque.

## PETG pellet temperatures (starting point)

- **Nozzle / lower zone:** ~**235 °C** (workable band ~220–245 °C).
- **Zones:** the Pulsar Atom is a 3-zone barrel (top/feed → middle → nozzle).
  Start **flat** across all zones, then, per Dyze's guidance, **drop the
  top/feed zone in ~10 °C steps** if pellets bridge or the screw whines/jams at
  the throat. Because the melt zone is long, **lower is often better** than
  filament PETG.
- **Dry the pellets.** PETG is hygroscopic; moisture causes sputter that mimics
  a stall.

Zone heaters are left as **commented, clearly-marked lines** in
`01_Heat_And_Soak.g` because the heater→zone index mapping depends on your
`config.g` (`M950`/`M563`). Set the primary (nozzle) temp works out of the box;
wire the extra zones to match your board.

## Safety

- Never extrude cold — the macros refuse below (target − 10 °C); `M302` cold-
  extrude protection should stay enabled in your `config.g` too.
- `03_Flow_Ladder.g` raises the E speed limit (`M203 E…`) so the ladder isn't
  silently clamped. **This persists until reboot or config reload** — re-run
  `config.g` (or reset) afterwards to restore your normal limit.
- Keep hands clear of the hot nozzle and have a tray ready for purge.

## Sources

- [DYZE Design — Pulsar™ Atom pellet extruder](https://dyzedesign.com/pulsar-atom-pellet-extruder/)
- [DYZE Design docs — Pulsar™ Atom](https://docs.dyzedesign.com/pulsar-atom.html)
- [PETG pellet extrusion temperature guidance (filament2print)](https://filament2print.com/en/pet-petg-cpe/1250-petg-pellets.html)
- [RepRapFirmware `M291` message boxes / choice buttons (Duet3D forum)](https://forum.duet3d.com/topic/31908/m291-s4-commands-not-working-on-rrf-3-5beta2)
