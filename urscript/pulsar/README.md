# Pulsar Atom + Duet 3 — UR5 CB3 control library (daemon-driven)

URScript helpers for driving a Pulsar Atom pellet extruder (Duet 3 /
RepRapFirmware) from a Universal Robots UR5 (CB3 controller) over a
Telnet socket. **All extrusion state lives on the Duet** — this library
is now a thin wrapper around Duet-side macros invoked via `M98`.

## Architecture

The UR robot owns motion. The Duet owns extrusion. A background daemon on
the Duet keeps the screw turning by feeding it **short** `G1 E` chunks
while `pulsar_running` is set. The live print program never blocks:

- **Preheat + purge** are the only blocking steps, and they've been
  split out into a separate routine (`preheat_purge.script`) the operator
  runs **once before** the job. The print program assumes they've been
  done.
- **Live control** (rate, pause, resume) is done by setting Duet globals
  directly over Telnet — `set global.pulsar_feed = …` and
  `set global.pulsar_running = …`. These are immediate meta-commands, so
  the screw responds within ~one chunk (~0.3–0.8 s), fire-and-forget,
  no socket read, no UR-side wait.

Screw speed (`pulsar_feed`) IS the deposition rate on a single screw, so
it's the flow knob — the old `M221` extrusion-factor path is retired
because it lagged a whole queued chunk. See `/duet/README.md`
"Responsiveness" for the stepper-vs-spindle reasoning.

```
                        Duet 3 / Pulsar Atom
                       ┌──────────────────────────────────────┐
   UR5 CB3             │ globals: pulsar_running, feed, chunk  │
   ┌──────┐            │                                       │
   │  UR  │ ─telnet─►  │   M98 P"pulsar_start.g" F600          │
   │ URS  │            │   set global.pulsar_feed = 350   (live)│
   │      │            │   set global.pulsar_running = false   │
   └──────┘            │                                       │
                       │   0:/sys/daemon.g (background)        │
                       │   ┌───────────────────────────────┐   │
                       │   │ if pulsar_running & feed>0:   │   │
                       │   │   G1 E{chunk} F{feed}  (short)│   │
                       │   │   G4 S{chunk/feed*60*0.9}     │   │
                       │   └───────────────────────────────┘   │
                       └──────────────────────────────────────┘
```

## Required Duet-side setup

See `/duet/` in this repo. Briefly:

1. Upload `/duet/sys/daemon.g` and `/duet/sys/pulsar_init.g` to the
   Duet's `0:/sys/`.
2. Upload all `/duet/macros/pulsar_*.g` files to `0:/macros/`.
3. Add `M98 P"pulsar_init.g"` to `config.g`.
4. Reboot the Duet.

Detailed install + verification steps live in `/duet/README.md`.

## Files in this directory

| File | Purpose |
|---|---|
| `lib_pulsar.script` | Function library only — no execution. Inline into a `Program()` block, or paste into a Grasshopper-emitted script. |
| `preheat_purge.script` | **Standalone, BLOCKING.** Run once on the pendant before a job: handshake, preheat (blocks on `M116`), purge (blocks on `M400`). Leaves heaters on. Keeps all the multi-minute waits out of the live print program. |
| `debug_harness.script` | Standalone runnable program. Steps through every helper with popups (incl. a live rate-change and pause/resume test). Still does its own preheat+purge so it can run cold in one go. Use it to validate before wiring up Grasshopper. |
| `grasshopper-integration.md` | **Map of GH Custom Command components** — Name, Declaration, and Command code for each insertion point. Read this when wiring the helpers into a GH-generated print program. |
| `snippets/01_setup.script` | Pulsar Setup — connect + handshake only (preheat/purge are done beforehand by `preheat_purge.script`). Non-blocking. |
| `snippets/02_start.script` | Pulsar Start — operator popup + start extrusion at a feed. |
| `snippets/03_pause.script` | Pulsar Pause — pause the screw for inserts/inspection, resume on OK. |
| `snippets/04_layer_change.script` | Pulsar layer change — pause / travel / resume. |
| `snippets/05_stop.script` | Pulsar Stop — pause, daemon off, cooldown. No popup. |
| `snippets/06_end.script` | Pulsar End — operator popup + close socket. |

## Function reference

### Connection
| Function | Purpose |
|---|---|
| `duet_open(ip, port)` | Open TCP socket named `"duet"`. |
| `duet_close()` | Close the socket. |
| `duet_send_line(line)` | Send one line, no response read. |
| `duet_send_line_and_read(line, timeout)` | Send + settle + read; returns response string or `""` on timeout. |
| `duet_send_m98(filename, params)` | Fire-and-forget `M98 P"0:/macros/<filename>"<params>`. Quotes injected via `socket_send_byte(34)` — see notes below. |
| `duet_send_m98_and_read(filename, params, timeout)` | Same, but blocks for the Telnet reply. Used by `pulsar_preheat()` to block on the Duet's internal `M116` wait. |
| `duet_handshake(timeout)` | Send `M115` and verify a response. Returns `True` / `False`. |

### Heating
| Function | Wraps | Purpose |
|---|---|---|
| `pulsar_clear_heater_faults()` | `M98 P"pulsar_clear_faults.g"` | Clear latched heater faults. |
| `pulsar_preheat(barrel, nozzle)` | `M98 P"pulsar_preheat.g" B<barrel> N<nozzle>` | Set both setpoints. **Blocks** until the Duet confirms both zones at temp (15 min timeout, pops a warning if it fires). No DIO, no polling loop — see Ready-signal pattern below. |
| `pulsar_cooldown()` | `M98 P"pulsar_cooldown.g"` | Both zones to 0 °C, tool off. |
| `pulsar_show_temp()` | `M105` (direct) | Pop up current temp reading. Call this right after `pulsar_preheat()` to show the operator the real numbers once preheat completes. |

### Future safety hook
| Function | Purpose |
|---|---|
| `wait_for_pulsar_enabled(debug, pin)` | Reserved for a future Duet→UR safety signal (e-stop / pause) once that DIO line exists. **Not used for temperature gating** — `pulsar_preheat()` handles that on its own. `debug=True` → no-op. `debug=False` → poll UR digital input `pin` until high. |

### Extrusion
| Function | Wraps | Purpose |
|---|---|---|
| `pulsar_purge(mm, feed)` | `M98 P"pulsar_purge.g" E<mm> F<feed>` | **Blocking** prime. Used only by `preheat_purge.script`, before a job. |
| `pulsar_start_extrusion(feed)` | `M98 P"pulsar_start.g" F<feed>` | Start the daemon — screw begins turning at `feed`. |
| `pulsar_set_rate(feed)` | `set global.pulsar_feed = <feed>` | **Live** rate/flow (screw speed). Immediate, fire-and-forget, ~1 chunk latency. |
| `pulsar_pause()` | `set global.pulsar_running = false` | **Live** pause — screw stops within ~1 chunk. |
| `pulsar_resume()` | `set global.pulsar_running = true` | **Live** resume at the current rate. |
| `pulsar_flow_off()` / `pulsar_flow_on(f)` | → `pulsar_pause()` / `pulsar_resume()` | Legacy aliases (flow % is no longer meaningful). Prefer pause/resume/set_rate. |
| `pulsar_stop_extrusion()` | `M98 P"pulsar_stop.g"` | Clear pulsar_running, release motor. |

### Retract (available, not used by the live flow)
| Function | Wraps | Purpose |
|---|---|---|
| `pulsar_retract(mm, feed)` | `M98 P"pulsar_retract.g" S<mm> F<feed>` | Relative-E retract. Largely inert on a screw; kept for experimentation. |
| `pulsar_unretract(mm, feed)` | `M98 P"pulsar_unretract.g" S<mm> F<feed>` | Relative-E unretract. |

## Default parameters (PETG baseline)

| Parameter | Value | Notes |
|---|---|---|
| Barrel zone (H0, "Top") | 215 °C | feed / compression zone. |
| Nozzle zone (H1, "Bottom") | 245 °C | metering / exit zone. |
| UR motion speed | 0.035 m/s | ≈ 35 mm/s; tune with feed. |
| Feed (`pulsar_feed`) | 600 mm/min | screw rate = deposition rate; PETG "usable" from pellet calibration (stall ~720). |
| Chunk (`pulsar_chunk`) | 5 mm | daemon-side; ~0.5 s/chunk at F600 → ~0.3–0.8 s live-control latency. |

Screw speed (`pulsar_feed`) is the volumetric rate — there's no separate
flow multiplier any more. Calibrate `feed` against your target bead by
weighing extrudate over a fixed time, or from the pellet-calibration
suite in `gcode-tests/pellet-calibration/`.

## Workflow

1. **Preheat + purge once**, up front, with `preheat_purge.script` on the
   pendant. Wait for it to report Ready. This is the only place the
   operator waits on the machine.
2. **Bench-test** the live path with `debug_harness.script` (it runs its
   own preheat+purge so you can test cold in one go) — watch the live
   rate-change and pause/resume steps respond within a fraction of a
   second.
3. **Print** by chaining: `01_setup` → `02_start` → motion + per-layer
   `04_layer_change` (and `03_pause` where needed) → `05_stop` →
   `06_end`, all generated by Grasshopper. See `grasshopper-integration.md`
   for the canonical Custom Command layout.

## Preheat/purge split & the blocking model

The multi-minute waits (preheat, purge) are **socket-blocking** and live
only in `preheat_purge.script`, run once before the job. RRF doesn't send
its Telnet "ok" until the whole macro — including the blocking `M116`
(at temp) or `M400` (purge done) inside it — has finished, so a single
blocking read guarantees the step genuinely completed. No polling, no
"does DWC look close enough" judgement call.

The **live** print program never blocks: it opens a socket, then drives
everything with fire-and-forget global sets (`pulsar_set_rate`,
`pulsar_pause`, `pulsar_resume`), which return no reply to wait on.

```
# once, beforehand (preheat_purge.script):
pulsar_preheat(215, 245)                # BLOCKS until both zones at temp
pulsar_purge(200, 300)                  # BLOCKS until purge move done

# live program:
pulsar_start_extrusion(600)             # screw runs continuously
pulsar_set_rate(350)                    # live rate change (~1 chunk)
pulsar_pause()                          # live pause (~1 chunk)
pulsar_resume()
```

`wait_for_pulsar_enabled(debug, pin)` still exists in the library but
is no longer part of this sequence — it's reserved for a future
Duet→UR safety signal (e-stop / pause) once that DIO line is wired.
The `pulsar_signal_ready.g` / `pulsar_signal_clear.g` macros on the
Duet side still fire (harmlessly, since their `M42` line is commented
out) — they're available for that future use, not for temperature
gating. See `/duet/README.md` for the hardware side.

For Grasshopper-driven prints, connect + clear-faults + preheat +
temp-report are all in the **Pulsar Setup** Custom Command, and the
operator popup + start are in **Pulsar Start** — see
`grasshopper-integration.md` for the canonical layout.

## Design rules

- One telnet call per state change. The daemon handles all in-between
  pacing.
- Never block on motion completion to send a socket command. UR and
  Duet run on independent timelines.
- Keep URScript linear. No multi-button popups. No conditional branching
  on socket return values beyond pass/fail.
- All numbers are constants at the top of the script. Grasshopper writes
  the constants; the helper logic stays the same.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Macros not found — `M98` errors with "file not found" | Macros not uploaded to `0:/macros/` | Re-upload from `/duet/macros/` and confirm filenames include `.g`. |
| `echo global.pulsar_running` returns nothing | `pulsar_init.g` not called from `config.g` | Add `M98 P"pulsar_init.g"` to `config.g` and reboot. |
| Robot reaches preheat but Pulsar doesn't heat | Heater fault latched | Call `pulsar_clear_heater_faults()` before `pulsar_preheat()`. |
| `pulsar_preheat()` pops the 15-min timeout warning | Heater hardware fault, thermistor disconnected, or M116 not reaching tolerance | Check Duet web UI; clear faults; verify wiring; check `M116` tolerance in RRF. |
| Preheat sets both zones to the same temperature | A heater that belongs to a multi-heater tool broadcasts any scalar-`S` command to every heater the tool owns (confirmed with `G10`, `M568`, and bare `M104 H<n>` — see `duet/README.md` "Why each heater has its own tool, set via M568 not G10") | Fixed by giving each zone its own single-heater tool (tool 1 = barrel/`H0`, tool 2 = nozzle/`H1`); `pulsar_preheat.g` uses `M568 P1 ... A2` / `M568 P2 ... A2`. If you see this again, check nobody merged the heaters back onto one tool. |
| Preheat popup returns instantly, "reported temps" popup comes back blank, no error anywhere | Heater target was set but the heater is still in **standby** state, not active — `G10` only writes target values, it doesn't change heater state, so `M116` sees nothing pending | Use `M568 Pn S<n> R<n> A2` instead of `G10`. The `A2` explicitly activates the heater; `A0` turns it off (used in `pulsar_cooldown.g`). |
| One zone overshoots target by >10 °C while the other holds | PID untuned for that heater, or thermistor / heater wiring swapped | Run `M303 H<n> S<target>` with the barrel empty. Verify each `Hn` drives the right physical zone via isolation test (see commit history). |
| Flow / pause changes lag by seconds-to-a-minute | `pulsar_chunk` too large — control waits out the in-flight move | Lower `global.pulsar_chunk` (default 5). This is the whole responsiveness lever; see `duet/README.md` "Responsiveness". |
| Screw stutters / bead pulses | Chunk so small the stop-start between chunks shows | Raise `pulsar_chunk` a little, or smooth transitions with `M566` (jerk) / `M201` (accel). |
| "Move duration too long" reappears | `pulsar_chunk` too large for current feed | Lower `global.pulsar_chunk`. |
| Screw won't turn after a rate change | `pulsar_feed` was set to 0 (daemon skips the chunk — it needs feed > 0) | Set a positive `pulsar_feed`; pause via `pulsar_running`, never via feed 0. |
| Bead too thin / thick | Feed (screw speed) too low / high, or motion too fast / slow | Adjust `pulsar_set_rate(<feed>)` or UR motion speed. |
| `socket_open` returns true but no comms | Cable, IP mismatch, or firewall | Run `duet_handshake()` after open and verify `M115` response. |

## CB3 / URScript constraints

- Indentation is strict — 2 spaces, no tabs.
- Function defs must precede their first call inside `Program()`.
- Don't rely on `socket_open`'s return value — verify with a handshake.
- `popup(...)` blocks until OK; multi-button popup return values are
  unreliable, so we don't use them.
- `to_str()` is required for every numeric concatenation.

## RepRapFirmware notes

- Each heater has its own tool — tool 0 (drive `D0` + fans, no heaters),
  tool 1 (`H0`, barrel), tool 2 (`H1`, nozzle). `pulsar_preheat.g`
  addresses them with `M568 P1 ... A2` / `M568 P2 ... A2`, not `G10` —
  `G10` only sets target values, `M568`'s `A` parameter is what actually
  activates the heater without needing to T-select the tool first. See
  `duet/README.md` for the full history of why.
- After the cs1↔cs2 swap in `M308`, H0 is the **Top / barrel / feed**
  zone and H1 is the **Bottom / nozzle / metering** zone.
- Rate/pause are done by setting `global.pulsar_feed` /
  `global.pulsar_running` directly over Telnet, not by `M221`. RRF runs a
  `set global.…` immediately (it's a meta-command, not queued motion), so
  it lands within one daemon iteration. `M221` was dropped from the live
  path because it only affects moves planned *after* it, so it lagged a
  whole queued chunk.
- The screw is a **stepper** (`M584 E0.1`), so it only turns while `G1 E`
  moves feed it — hence the short-chunk daemon. A true "always spinning,
  set the RPM" spindle (`M3 S<rpm>`) needs a spindle-type motor/driver,
  which is how commercial pellet rigs get genuinely instant control; a
  Duet stepper can't do that, so short chunks are the ceiling here.
