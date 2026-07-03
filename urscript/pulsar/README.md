# Pulsar Atom + Duet 3 — UR5 CB3 control library (daemon-driven)

URScript helpers for driving a Pulsar Atom pellet extruder (Duet 3 /
RepRapFirmware) from a Universal Robots UR5 (CB3 controller) over a
Telnet socket. **All extrusion state lives on the Duet** — this library
is now a thin wrapper around Duet-side macros invoked via `M98`.

## Architecture

The UR robot owns motion. The Duet owns extrusion. They communicate over
TCP/23 (Telnet) with a small set of `M98` calls — start, stop, flow,
retract, preheat. A background daemon on the Duet keeps the screw
turning while a `pulsar_running` flag is set; the UR doesn't have to
think about move-duration limits or top-up timing.

```
                        Duet 3 / Pulsar Atom
                       ┌──────────────────────────────────────┐
   UR5 CB3             │ globals: pulsar_running, feed, chunk │
   ┌──────┐            │                                      │
   │  UR  │ ─telnet─►  │   M98 P"pulsar_start.g" F900 R100    │
   │ URS  │  M98 only  │   → sets globals                     │
   └──────┘            │                                      │
                       │   0:/sys/daemon.g (background)       │
                       │   ┌──────────────────────────────┐   │
                       │   │ if pulsar_running:           │   │
                       │   │   G1 E{chunk} F{feed}        │   │
                       │   │   G4 S{dwell}                │   │
                       │   └──────────────────────────────┘   │
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
| `debug_harness.script` | Standalone runnable program. Steps through every helper with popups. Use this on the robot to validate the workflow before wiring up Grasshopper. |
| `grasshopper-integration.md` | **Map of GH Custom Command components** — Name, Declaration, and Command code for each insertion point. Read this when wiring the helpers into a GH-generated print program. |
| `snippets/01_setup.script` | Pulsar Setup — connect + preheat (reference; GH guide is canonical). |
| `snippets/02_start.script` | Pulsar Start — wait + popup + start extrusion. |
| `snippets/03_pause.script` | Pulsar Pause — scripted mid-print pause for inserts/inspection. |
| `snippets/04_layer_change.script` | Pulsar Pre/Post-Travel pair for layer changes. |
| `snippets/05_stop.script` | Pulsar Stop — flow off, retract, daemon off, cooldown. No popup. |
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
| `pulsar_start_extrusion(feed, flow)` | `M98 P"pulsar_start.g" F<feed> R<flow>` | Start the daemon — screw begins turning. |
| `pulsar_flow_on(flow)` | `M98 P"pulsar_flow.g" S<flow>` | Set M221 flow %. |
| `pulsar_flow_off()` | `M98 P"pulsar_flow.g" S0` | M221 S0 — bead off, daemon keeps queueing. |
| `pulsar_retract(mm, feed)` | `M98 P"pulsar_retract.g" S<mm> F<feed>` | Relative-E retract. |
| `pulsar_unretract(mm, feed)` | `M98 P"pulsar_unretract.g" S<mm> F<feed>` | Relative-E unretract. |
| `pulsar_stop_extrusion()` | `M98 P"pulsar_stop.g"` | Clear pulsar_running, zero flow, release motor. |

## Default parameters (PLA baseline)

| Parameter | Value | Notes |
|---|---|---|
| Barrel zone (H0, "Top") | 190 °C | feed / compression. PLA values; for PETG try 220 °C. |
| Nozzle zone (H1, "Bottom") | 215 °C | metering / exit. PLA values; for PETG try 245 °C. |
| UR motion speed | 0.035 m/s | ≈ 35 mm/s |
| Layer height | 1.0 mm | |
| Bead width | 2.5 mm | |
| Volumetric flow | ≈ 90 mm³/s | layer × width × speed |
| Throughput | ≈ 400 g/h | at material density ≈ 1.25 g/cm³ |
| Retract | 3 mm @ 600 mm/min | |
| Feed (`F`) | 900 mm/min | screw rate; tune to match volumetric target |
| Chunk (`pulsar_chunk`) | 1000 mm | daemon-side; ≈ 67 s of extrusion at F900 |
| Initial flow (`M221 S`) | 100 % | per-layer trim with `M221` |

The continuous chunks emitted by the daemon don't encode volumetric flow
directly — they encode screw speed via the extruder's steps/mm
calibration. Calibrate `feed` empirically against the 90 mm³/s target by
weighing extrudate over a fixed time at flow 100 %.

## Workflow

1. **Bench-test** with `debug_harness.script` running directly on the
   UR. Step through every popup, watching the Pulsar respond at each
   stage.
2. **Print** by chaining: `01_setup` → `02_start` → motion + per-layer
   `04_layer_change` pairs (and `03_pause` where needed) → `05_stop` →
   `06_end`, all generated by Grasshopper. See `grasshopper-integration.md`
   for the canonical Custom Command layout.

## Ready-signal pattern

Preheat is **socket-blocking**, not DIO-gated. RRF doesn't send its
Telnet "ok" reply until the whole macro — including the blocking
`M116` inside `pulsar_preheat.g` — has finished, so a single blocking
read on the UR side is enough to guarantee both zones are genuinely at
temperature. No polling loop, no operator judgement call about whether
DWC "looks close enough".

```
pulsar_preheat(190, 215)                # BLOCKS until both zones at temp
pulsar_show_temp()                      # report the actual reading
popup("Press Ready to start", ...)      # operator gate (GH-emitted)
pulsar_start_extrusion(900, 100)        # daemon takes over
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
| Screw stalls briefly every minute | `pulsar_dwell` too long | From DWC console: `set global.pulsar_dwell = <smaller>`. Recover stable value, then update the default in `pulsar_init.g`. |
| "Move duration too long" reappears | `pulsar_chunk` too large for current feed | Lower `global.pulsar_chunk` (default 1000 should be safe for F up to ~9000). |
| Bead too thin | Flow % too low, or feed too low, or motion too fast | Raise `M221 S`, raise `feed`, or slow UR motion. |
| Bead too thick | Inverse of above. | |
| Stringing between layers | Retract too small or unretract too soon | Increase `retract_mm`; lift Z before unretract. |
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
- `M221 S0` is "no flow" — the daemon keeps queueing chunks, the
  multiplier just pins the screw speed at 0. The pellet screw stops
  cleanly without disturbing the move queue.
