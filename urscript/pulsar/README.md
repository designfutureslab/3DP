# Pulsar Atom + Duet 3 — UR5 CB3 control library

URScript helpers for driving a Pulsar Atom pellet extruder (Duet 3 /
RepRapFirmware) from a Universal Robots UR5 (CB3 controller) over a Telnet
socket.

## What this is

The UR robot owns motion. The Duet owns extrusion. They communicate over
TCP/23 (Telnet) with a small set of G-code messages. Real-time
synchronisation is deliberately avoided — the screw runs continuously and we
modulate flow with `M221`.

```
        UR5 CB3                    Duet 3 / Pulsar Atom
        +------+   socket "duet"   +-------------------+
        |  UR  |  ───────────────► | RepRapFirmware    |
        | URS  |    Telnet :23     | M104/M109/M221/G1 |
        +------+                   +-------------------+
```

## Files

| File | Purpose |
|---|---|
| `lib_pulsar.script` | Function library only — no execution. Inline into a `Program()` block, or paste into a Grasshopper-emitted script. |
| `debug_harness.script` | Standalone runnable program. Steps through every helper with popups. Use this on the robot to validate the workflow before wiring up Grasshopper. |
| `snippets/01_preamble.script` | Print-start block for Grasshopper-emitted programs. |
| `snippets/02_layer_change.script` | Layer-change block for Grasshopper-emitted programs. |
| `snippets/03_end_print.script` | End-of-print block for Grasshopper-emitted programs. |

## Function reference

### Connection
| Function | Purpose |
|---|---|
| `duet_open(ip, port)` | Open TCP socket named `"duet"`. |
| `duet_close()` | Close the socket. |
| `duet_send_line(line)` | Send one line, no response read. |
| `duet_send_line_and_read(line, timeout)` | Send + settle + read; returns response string or `""` on timeout. |
| `duet_handshake(timeout)` | Send `M115` and verify a response. Returns `True` / `False`. |

### Heating
| Function | Purpose |
|---|---|
| `pulsar_clear_heater_faults()` | `M562` — clear any latched fault state. |
| `pulsar_preheat_material(zone1, zone2)` | Set both setpoints + block on `M109` until reached. Unattended-friendly, silent. |
| `pulsar_preheat_material_polled(z1, z2, tolerance, max_polls)` | Set both setpoints + poll `M105` in a loop with a popup per poll. Operator-attended, exits on target ±`tolerance` or `max_polls`. |
| `parse_temp(resp, tag)` | Helper — extract numeric value following `tag` (e.g. `"T0:"`) in an `M105` response. Returns `-1.0` if not found. |
| `pulsar_cooldown()` | Set both zones to 0 °C. |
| `pulsar_show_temp()` | Pop up current `M105` reading. |

#### Preheat strategies

Two variants, pick by use case:

| When | Use | Behaviour |
|---|---|---|
| Grasshopper-driven print, no operator at the pendant | `pulsar_preheat_material` | Sends `M104` setpoints, then blocks on `M109` until each zone is at temp. No popups, no feedback — script just sits silently for 3–5 min. Fast path to "ready". |
| Bench testing, debug harness, anything where you want eyes on the heat-up | `pulsar_preheat_material_polled` | Sends `M104` setpoints, then loops `M105` polls with one popup per iteration showing current vs. target for both zones. Operator clicks OK to advance. Exits when both zones reach `target − tolerance` or after `max_polls` polls. |

The blocking version's silent wait was confusing in early bench tests
(no popup for the full preheat duration looked like the script had hung).
The polled version makes progress visible at the cost of click-through.

### Extrusion
| Function | Purpose |
|---|---|
| `pulsar_start_extrusion(feed, flow)` | Begin continuous extrusion at `flow %` and `feed mm/min`. |
| `pulsar_flow_on(flow)` | Set `M221 S<flow>`. |
| `pulsar_flow_off()` | Set `M221 S0`. |
| `pulsar_retract(mm, feed)` | Relative-E retract. |
| `pulsar_unretract(mm, feed)` | Relative-E unretract. |
| `pulsar_stop_extrusion()` | Flow off + `M84 E`. |

## Default parameters (Material, baseline)

| Parameter | Value | Notes |
|---|---|---|
| Zone 1 (barrel) | 190 °C | feed / compression — heater `H0`. PLA values; PETG typically needs higher (≈ 220 / 245). |
| Zone 2 (nozzle) | 215 °C | metering — heater `H1`. PLA values; PETG typically needs higher. |
| UR motion speed | 0.035 m/s | ≈ 35 mm/s |
| Layer height | 1.0 mm | |
| Bead width | 2.5 mm | |
| Volumetric flow | ≈ 90 mm³/s | layer × width × speed |
| Throughput | ≈ 400 g/h | at material density ≈ 1.25 g/cm³ |
| Retract | 3 mm @ 600 mm/min | |
| Continuous-extrude feed (`F`) | 900 mm/min | tune to match volumetric target |
| Initial flow (`M221 S`) | 100 % | per-layer trim with `M221` |

The continuous `G1 E... F...` does not encode volumetric flow directly — it
encodes screw speed via the extruder's steps/mm calibration. Calibrate
`feed` empirically against the 90 mm³/s target by weighing extrudate over a
fixed time at flow 100 %.

## Workflow

1. **Bench-test** with `debug_harness.script` running directly on the UR.
   Step through every popup, watching the Pulsar respond at each stage.
2. **Print** by chaining: `01_preamble` → motion + per-layer
   `pulsar_flow_on` / `02_layer_change` pairs → `03_end_print`, all generated
   by Grasshopper.

## Design rules

- Minimise telnet calls. One per state change. Never per motion segment.
- Never block on motion completion to send a socket command. The two run
  on independent timelines.
- Keep URScript linear. No multi-button popups. No conditional branching on
  socket return values beyond pass/fail.
- All numbers are constants at the top of the script. Grasshopper writes
  the constants; the helper logic stays the same.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Robot reaches preheat but Pulsar doesn't heat | Heater fault latched | Run `pulsar_clear_heater_faults()` before `pulsar_preheat_material()`. |
| `M109` never returns | Heater hardware fault, or thermistor disconnected | Check Duet web UI; clear faults; verify wiring. |
| Bead too thin | Flow % too low, or feed too low, or motion too fast | Raise `M221 S`, raise `feed`, or slow UR motion. |
| Bead too thick | Inverse of above. | |
| Extruder stalls | Feed (`F`) too high for screw torque | Lower `feed`, raise zone 1 temp slightly. |
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

- `M104 Sxxx Hn` / `M109 Sxxx Hn` use the heater index. Verify your Duet
  config maps `H0` to the barrel and `H1` to the nozzle. If you migrate to a
  different firmware, switch to `M116 Hn` for the wait.
- `M221 S0` is "no flow" — the long G1 is still queued, the multiplier just
  pins the screw speed at 0. The pellet screw stops cleanly.
- `M84 E` releases only the extruder motor. The XYZ steppers aren't involved
  here — UR controls all motion.
