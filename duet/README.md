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
| `macros/pulsar_preheat.g` | `0:/macros/pulsar_preheat.g` | Set + activate both zones via `M568 P1 S<barrel> R<barrel> A2` / `M568 P2 S<nozzle> R<nozzle> A2` (each zone's own single-heater tool), block until reached with `M116 P1` / `M116 P2`. Echoes the parsed temps to the console. See "Why each heater has its own tool" below for why. |
| `macros/pulsar_start.g` | `0:/macros/pulsar_start.g` | Begin continuous extrusion. Sets `pulsar_running = true`. |
| `macros/pulsar_stop.g` | `0:/macros/pulsar_stop.g` | Clear `pulsar_running`, zero flow, release motor. |
| `macros/pulsar_flow.g` | `0:/macros/pulsar_flow.g` | `M221 S<percent>` — modulate flow without stopping the screw. |
| `macros/pulsar_retract.g` | `0:/macros/pulsar_retract.g` | Relative-E retract. |
| `macros/pulsar_unretract.g` | `0:/macros/pulsar_unretract.g` | Relative-E unretract. |
| `macros/pulsar_cooldown.g` | `0:/macros/pulsar_cooldown.g` | Both zone heaters off (`M568 P1/P2 A0`). |
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

## Why each heater has its own tool, set via M568 not G10

Four attempts, in order, all confirmed on hardware:

1. **Both heaters under tool 0's `H` list** (`M563 P0 ... H1:0`). Any
   command that set temperature with a single scalar `S` — `G10 P0 S<n>`,
   `M568 P0 S<n>`, even bare `M104 H<n> S<n>` — got routed through the
   tool and broadcast that one value to *every* heater the tool owned,
   silently overwriting the other zone's target. Reproduced with two
   back-to-back bare `M104 H0 S150` / `M104 H1 S170` commands (no macro,
   no colon-list): both heaters ended up at 170. Verified via
   `M409 K"heat.heaters"`.
2. **Heaters removed from any tool**, addressed via bare `M104 H0` /
   `M104 H1`. Commands were accepted with no error, but the DWC Tools
   panel showed the heater as `n/a` and neither zone actually heated —
   heaters that belong to no tool don't enter the "active" state on this
   firmware.
3. **Each heater got its own single-heater tool**, set via `G10 P1 S<n>`
   / `G10 P2 S<n>`. Temperatures visibly changed this time, but the
   heaters stayed in **standby** state — `G10` only writes the
   active/standby target values, it doesn't change which state
   (off/standby/active) the heater is actually in, and without
   `T`-selecting the tool nothing switched it to active. Result: the
   preheat popup returned instantly instead of blocking (`M116 P1`/`P2`
   saw nothing pending), and the "reported temps" popup came back blank.
4. **Same one-heater-per-tool split, but activate with `M568 ... A2`
   instead of `G10`** (current approach). `M568`'s `A` parameter
   explicitly forces the heater into active state without needing to
   `T`-select the tool — this is the one thing that reliably activated
   heaters throughout this whole investigation (see attempt 1, which
   *did* heat, just to the wrong shared value). Safe here because each
   tool owns exactly one heater, so there's still nothing for the `S`/`R`
   values to broadcast across.

If you ever merge `H0` and `H1` back onto one tool to "simplify," attempt
1's bug comes back. If you ever swap `M568 ... A2` back for bare `G10`,
attempt 3's "sets temp but never activates" bug comes back.

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

## Duet→UR ready signal (hardware DIO) — reserved for future safety use

Earlier revisions used this signal to tell the UR when preheat had
finished. That's no longer how temperature readiness works: the UR now
blocks directly on the Telnet reply from `M98 P"pulsar_preheat.g" ..."`
— RRF doesn't send "ok" back until the whole macro, including the
`M116` inside it, has completed. So the UR knows both zones are at
temp without needing this wire at all.

The DIO plumbing is kept in place for a **different**, not-yet-built
purpose: a Duet→UR safety signal (e-stop / pause) that would need its
own trigger logic distinct from "heaters at temp".

```
   Duet 3 (out6 / out7 / ioN)              UR5 CB3
   ┌────────────────┐                      ┌────────────────┐
   │ M42 P<pin> S1  │ ───── 24 V wire ─────│ DI<n>          │
   │ when safe      │                      │ get_standard_  │
   │                │ ◄──── 0 V (GND) ─────│  digital_in()  │
   └────────────────┘                      └────────────────┘
```

`pulsar_preheat.g` still fires `M98 P"0:/macros/pulsar_signal_ready.g"`
after its `M116` returns, and `pulsar_stop.g` / `pulsar_cooldown.g`
still fire `pulsar_signal_clear.g` — harmless no-ops today since both
signal macros have their `M42` line commented out. Repurpose these (or
write new ones) when the actual safety-signal use case is designed;
don't assume they still mean "preheat done".

On the UR side, `wait_for_pulsar_enabled(debug, pin)` still exists in
`lib_pulsar.script` for this future use, but isn't called anywhere in
the current preheat/start sequence.

## RRF conditional-block syntax note

Every `if` / `else` / `while` block in these macros uses **dedent-based
termination** — no explicit block-terminator keyword at all. The block
ends when the next line at the same or lower indentation appears (or
at EOF).

Bench-tested on Ric's Duet (RRF 3.6): both bare `end` and `endif` get
rejected with "Bad command: X" — RRF parses them as G-code command
names rather than block terminators. Dedent works reliably. If you're
authoring a new macro, do NOT introduce `end` / `endif` / `endwhile`.

Structure everything so the next command at column 0 (or a comment)
follows immediately after the last indented line of the block, e.g.:

```
if condition
  action
next_command_at_col_0
```

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
