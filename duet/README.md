# Duet 3 — Pulsar Atom extrusion control (daemon + macros)

RepRapFirmware-side companion to `urscript/pulsar/`. All extrusion state
lives here on the Duet: a background daemon keeps the screw turning while
the UR fires short `M98` commands to start, stop, retract, and modulate
flow.

## Why this exists

The original "UR sends one long `G1 E1000000 F900`" pattern hit RRF's
per-move duration cap (~10 min) and required the UR to top up
periodically. Moving the keep-it-spinning logic onto the Duet:

- One telnet call per state change (start, stop, flow, retract). No
  re-sending from the UR.
- No "move duration too long" errors — the daemon queues small chunks
  (~1000 mm at F900 ≈ 67 s each).
- Print state and safety logic live in one place.

## Files

| File | Destination on Duet SD | Purpose |
|---|---|---|
| `sys/config.g` | `0:/sys/config.g` | Reference copy of the live Duet config. Includes the `M98 P"pulsar_init.g"` hook. Not auto-deployed — the Duet has its own working copy. |
| `sys/daemon.g` | `0:/sys/daemon.g` | Background loop. RRF auto-runs while booted. |
| `sys/pulsar_init.g` | `0:/sys/pulsar_init.g` | Declares the four globals the daemon reads. Called once from `config.g`. |
| `macros/pulsar_preheat.g` | `0:/macros/pulsar_preheat.g` | Set both zone targets, block until reached. |
| `macros/pulsar_start.g` | `0:/macros/pulsar_start.g` | Begin continuous extrusion. Sets `pulsar_running = true`. |
| `macros/pulsar_stop.g` | `0:/macros/pulsar_stop.g` | Clear `pulsar_running`, zero flow, release motor. |
| `macros/pulsar_flow.g` | `0:/macros/pulsar_flow.g` | `M221 S<percent>` — modulate flow without stopping the screw. |
| `macros/pulsar_retract.g` | `0:/macros/pulsar_retract.g` | Relative-E retract. |
| `macros/pulsar_unretract.g` | `0:/macros/pulsar_unretract.g` | Relative-E unretract. |
| `macros/pulsar_cooldown.g` | `0:/macros/pulsar_cooldown.g` | Both zone targets to 0, tool off. |
| `macros/pulsar_clear_faults.g` | `0:/macros/pulsar_clear_faults.g` | `M562` on both heaters. |
| `macros/pulsar_signal_ready.g` | `0:/macros/pulsar_signal_ready.g` | Assert the Duet→UR "ready" DIO. Called automatically from `pulsar_preheat.g`. **Placeholder — uncomment the `M42` line once the wire is in place.** |
| `macros/pulsar_signal_clear.g` | `0:/macros/pulsar_signal_clear.g` | Drop the Duet→UR "ready" DIO. Called automatically from `pulsar_stop.g` and `pulsar_cooldown.g`. Same `M42` placeholder. |

## One-time install

1. **Upload the files** via DWC → System tab (for `sys/`) and Macros tab
   (for `macros/`). Keep filenames exactly as listed above — `daemon.g`
   in particular *must* be that name for RRF to pick it up.
2. **Edit `config.g`** and add one line, anywhere after the tool
   definition (`M563 P0 ...`):

   ```
   M98 P"pulsar_init.g"
   ```

3. **Reboot the Duet** (`M999` from the console, or power-cycle).
4. **Verify** — from the DWC console:
   - `echo global.pulsar_running` should return `false`.
   - `echo global.pulsar_feed` should return `900`.
   - DWC's "Object Model" pane should show the daemon ticking (sleeping
     in its idle branch).

## Daemon globals

The four globals the daemon reads:

| Global | Default | Meaning |
|---|---|---|
| `pulsar_running` | `false` | While true, the daemon queues extrusion chunks. |
| `pulsar_feed` | `900` | F-value (mm/min) for each chunk. |
| `pulsar_chunk` | `1000` | mm of E queued per chunk. |
| `pulsar_dwell` | `60` | Seconds the daemon sleeps after queueing a chunk. Recalculated by `pulsar_start.g` as `chunk × 60 / feed × 0.95`. |

`pulsar_chunk` and `pulsar_dwell` are tuned so the next chunk queues
slightly before the previous finishes — queue depth stays near one
chunk, no stalls, no "move duration too long" errors.

## Public API (called from URScript over telnet)

```
M98 P"pulsar_clear_faults.g"
M98 P"pulsar_preheat.g" B<barrel> N<nozzle>      ; blocks until at temp
M98 P"pulsar_start.g"   F<feed>   R<flow_pct>
M98 P"pulsar_flow.g"    S<percent>                ; 0 = bead off, no stall
M98 P"pulsar_retract.g"   S<mm> F<mm_per_min>
M98 P"pulsar_unretract.g" S<mm> F<mm_per_min>
M98 P"pulsar_stop.g"
M98 P"pulsar_cooldown.g"
```

All parameters are optional; sensible defaults are baked into the
macros. The URScript helper functions in `urscript/pulsar/lib_pulsar.script`
wrap each of these.

## Tuning notes

- **Chunk too small** (`pulsar_chunk` low) → daemon issues commands very
  frequently, more I/O overhead on the Duet, but very tight queue
  control. Default 1000 mm is a balance.
- **Dwell too long** → screw stalls briefly between chunks. Bead has a
  visible pulse. Lower `global.pulsar_dwell` manually or shorten
  `pulsar_chunk`.
- **Dwell too short** → queue grows. If it grows enough that a single
  queued chunk exceeds RRF's move-duration cap, you'll see "move
  duration too long" again. Raise dwell or lower chunk.

## Duet→UR ready signal (hardware DIO)

The UR no longer polls the Duet to know when it's safe to start motion —
the Duet asserts a digital output once both heaters reach setpoint and
the UR reads that as a digital input.

```
   Duet 3 (out6 / out7 / ioN)              UR5 CB3
   ┌────────────────┐                      ┌────────────────┐
   │ M42 P<pin> S1  │ ───── 24 V wire ─────│ DI<n>          │
   │ when ready     │                      │ get_standard_  │
   │                │ ◄──── 0 V (GND) ─────│  digital_in()  │
   └────────────────┘                      └────────────────┘
```

`pulsar_preheat.g` fires `M98 P"pulsar_signal_ready.g"` after its
`M116` returns; `pulsar_stop.g` and `pulsar_cooldown.g` fire
`M98 P"pulsar_signal_clear.g"`. Both signal macros currently have their
`M42` line commented — uncomment with the correct Duet output pin once
the wire is in.

On the UR side, `wait_for_pulsar_enabled(debug, pin)` blocks until the
input goes high. While `debug=True`, it shows a confirmation popup
instead, so the workflow is fully testable without the wire.

## RRF conditional-block syntax note

All macros use `endif` / `endwhile` (compact form) as the block
terminator, not bare `end`. RRF 3.6 rejects bare `end` with "Bad
command: end" — first hit during bench testing was line 11 of
`pulsar_init.g` (the first `end` after the initial `if !exists(...)`).
Confirmed working: `endif` and `endwhile`. Do not switch back to
`end`.

## Safety

- The daemon does **not** check heater state. If you fire
  `pulsar_start.g` with cold heaters the screw will try to push cold
  pellets — protect against this in URScript by always calling
  `pulsar_preheat.g` first.
- `pulsar_stop.g` only clears the flag. Already-queued chunks will
  finish executing before motion truly stops. For an immediate stop use
  `M0` or `M112` (emergency stop) instead.
- The existing `M570 H0 P600 / M570 H1 P600` thermal-runaway timeouts
  in `config.g` apply unchanged.
- Future: the same DIO pattern can carry e-stop / pause state both ways.
  E.g., a second wire UR→Duet that the Duet's `daemon.g` reads — when
  low, the daemon stops queueing chunks and clears flow. Not implemented
  yet; design is open.
