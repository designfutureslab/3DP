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
| `sys/daemon.g` | `0:/sys/daemon.g` | Background loop. RRF auto-runs while booted. Feeds the screw short `G1 E` chunks while `pulsar_running`; computes its own inter-chunk dwell from chunk/feed. |
| `sys/pulsar_init.g` | `0:/sys/pulsar_init.g` | Declares the globals the daemon reads (`pulsar_running`, `pulsar_feed`, `pulsar_chunk`). Called once from `config.g`. |
| `macros/pulsar_preheat.g` | `0:/macros/pulsar_preheat.g` | Set + activate both zones via `M568 P1 S<barrel> R<barrel> A2` / `M568 P2 S<nozzle> R<nozzle> A2` (each zone's own single-heater tool), block until reached with `M116 P1` / `M116 P2`. Echoes the parsed temps to the console. See "Why each heater has its own tool" below for why. |
| `macros/pulsar_start.g` | `0:/macros/pulsar_start.g` | Begin continuous extrusion. **Clean-slate:** stops + drains (`M400`) first, resets E origin + `M221 100`, then sets `pulsar_feed` and `pulsar_running = true`. Starting IS the reset — a print can't inherit stale state from a previous run. |
| `macros/pulsar_purge.g` | `0:/macros/pulsar_purge.g` | **Blocking** prime — `G1 E<mm> F<feed>` + `M400`. Run before a job (from `preheat_purge.script` or a DWC button), not on the live path. |
| `macros/pulsar_stop.g` | `0:/macros/pulsar_stop.g` | Canonical safe-idle: `pulsar_running = false`, **`M400` to drain the queue** (so "stopped" means stopped, not a few cm of buffered ooze), `M221 S0`, release motor. Heaters left on. |
| `macros/debug/*.g` | `0:/macros/debug/` | DWC button macros for bench debugging — Status, Resume, Pause, Stop & Clear, Prime 10 mm, Cooldown. See "Debug buttons" below. |
| `macros/pulsar_flow.g` | `0:/macros/pulsar_flow.g` | `M221 S<percent>`. **Legacy** — rate is now screw speed via `pulsar_feed`; kept only as an optional extrusion-factor trim for DWC. |
| `macros/pulsar_retract.g` | `0:/macros/pulsar_retract.g` | Relative-E retract. Largely a no-op on a screw; not used by the live flow. |
| `macros/pulsar_unretract.g` | `0:/macros/pulsar_unretract.g` | Relative-E unretract. Not used by the live flow. |
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

## Responsiveness: why short chunks, and how live control works

Our Pulsar screw is a **stepper** (`config.g`: `M584 E0.1`). A stepper
only turns while `G1 E` moves feed it, so "run continuously" means "keep
feeding it moves" — that's what `daemon.g` does. (A commercial pellet
extruder like the Rapid Fusion PE320 drives its screw as a **spindle**
with `M3 S<rpm>`, which runs continuously and changes speed instantly
with no motion queue — genuinely instant, but not something a stepper on
a Duet driver can replicate.)

The original daemon queued a single **1000 mm @ F900 ≈ 67 s** move at a
time. Because `M221`/pause only affect moves planned *after* them, any
control change waited out that whole in-flight move — up to ~67 s of lag.
That was the unresponsiveness, not a bug.

Fix: keep the screw fed with **short** chunks (default 5 mm) and control
everything by setting Duet globals directly over Telnet:

- **Rate** — `set global.pulsar_feed = <mm/min>`. Screw speed *is* the
  deposition rate on a single screw, so this is the "flow" knob. `M221`
  is no longer used for live rate (it lagged a whole chunk).
- **Pause / resume** — `set global.pulsar_running = false` / `true`.

`set global.…` is an immediate meta-command (not queued motion), so RRF
applies it at once; the daemon picks it up on its next loop iteration.
With a 5 mm chunk that's ~0.3–0.8 s end to end — the stepper ceiling.
Drop `pulsar_chunk` toward 3 for snappier, raise it if the screw
stutters.

### The daemon loops internally — don't rely on RRF re-invocation

**Critical:** `daemon.g` must feed chunks from a `while` loop *inside*
the file, not one chunk per invocation. RRF only re-invokes `daemon.g`
every few seconds when it returns quickly (measured ~5–6 s on Ric's
Duet). An earlier version fed a single chunk then returned, so the screw
got one 5 mm blip every 5–6 s — a stutter that looked exactly like a
low-feed problem but wasn't (feed was a correct 700). The `while` loop
keeps the screw fed tightly regardless of RRF's re-invocation cadence,
and re-reads `pulsar_feed` / `pulsar_running` each iteration so live
control still bites within ~1 chunk. When `pulsar_running` goes false
the loop exits, the file returns, and RRF re-invokes it a few seconds
later to idle until the next run. If you ever refactor `daemon.g` back
to "one chunk per invocation," the 5–6 s stutter returns.

### Daemon globals

| Global | Default | Meaning |
|---|---|---|
| `pulsar_running` | `false` | While true, the daemon's internal `while` loop feeds one chunk per iteration. Clear it to pause (loop exits within ~1 chunk). |
| `pulsar_feed` | `600` | F-value (mm/min) — the live rate knob. **Must stay > 0 while running** (the daemon divides the dwell by it; pause via the flag, never via feed 0). |
| `pulsar_chunk` | `5` | mm of E per chunk. Short = responsive. |

There is no `pulsar_dwell` global any more — `daemon.g` computes the
inter-chunk dwell inline as `chunk / feed × 60 × 0.9` every iteration, so
a live feed change re-paces itself (the `×0.9` issues the next chunk just
before the current finishes → queue depth ~1, continuous motion).

## Debug buttons (DWC Macros tab)

Files in `0:/macros/debug/` show up as a **debug** folder in the DWC
Macros tab, each a clickable button — handy at the bench without typing
console commands. Upload the whole `duet/macros/debug/` folder.

| Button | Does |
|---|---|
| `1_Status` | Echoes `pulsar_running` / `pulsar_feed` / `pulsar_chunk` to the console (temps are already live on the dashboard). |
| `2_Resume` | Starts the screw at the current `pulsar_feed` (bumps it to 600 if it's 0). |
| `3_Pause` | Stops the screw, leaves everything else as-is. |
| `4_Stop_and_Clear` | **Panic button.** Full `pulsar_stop.g` — daemon off, queue drained, flow 0, motor released. Heaters stay on. |
| `5_Prime_10mm` | Manually extrudes 10 mm to prime/clear the nozzle (stops the daemon first so it doesn't fight the move). Zones should be at temp. |
| `6_Cooldown` | Both heater zones off. |

These call the same macros / set the same globals the robot does, so
nothing here is a special code path — it's the production plumbing with
a button on it.

## Resetting state between prints

You don't need to manually reset anything between prints. `pulsar_start.g`
does a clean-slate start every time: it clears `pulsar_running`, drains
the queue with `M400`, re-zeroes the E origin and `M221`, and only then
sets the feed and starts. So a stale `pulsar_running = true` or a
half-drained queue from a previous run (or from bench testing) can't leak
into the next print. If a student aborts a print mid-run, hit
**Stop & Clear** (or just start the next print — it resets itself).

## Public API (called from URScript over telnet)

```
M98 P"pulsar_clear_faults.g"
M98 P"pulsar_preheat.g" B<barrel> N<nozzle>      ; blocks until at temp
M98 P"pulsar_purge.g"   E<mm> F<mm_per_min>      ; blocks until purge done
M98 P"pulsar_start.g"   F<feed>                   ; screw runs continuously
set global.pulsar_feed = <mm_per_min>             ; live rate (immediate)
set global.pulsar_running = false                 ; pause (immediate)
set global.pulsar_running = true                  ; resume (immediate)
M98 P"pulsar_stop.g"
M98 P"pulsar_cooldown.g"
```

Macro parameters are optional; sensible defaults are baked in. The
URScript helper functions in `urscript/pulsar/lib_pulsar.script` wrap
each of these (`pulsar_set_rate`, `pulsar_pause`, `pulsar_resume`, …).

## Tuning notes

Dwell is no longer a separate global — `daemon.g` derives it from
`pulsar_chunk` and `pulsar_feed` each iteration (`chunk / feed × 60 ×
0.9`), so the only knob is chunk size:

- **Chunk too small** → daemon iterates very frequently (more Duet I/O),
  and the screw stop-starts more often between chunks. If you see flow
  ripple, raise `pulsar_chunk` a little or tune `M566` (jerk) / `M201`
  (accel) so the transitions between chunks are smoother.
- **Chunk too large** → less responsive: pause and rate changes wait up
  to one chunk to land. At the extreme (the old 1000 mm) you're back to
  ~minute-scale lag, and a single chunk can exceed RRF's move-duration
  cap ("move duration too long"). Default 5 mm keeps response ~0.3–0.8 s.
- **`pulsar_feed` must stay > 0 while running** — it divides the dwell.
  Pause by clearing `pulsar_running`, never by setting feed to 0.

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
