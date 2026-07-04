# Pulsar control via Grasshopper Custom Commands

How to weave Pulsar extrusion control into a Grasshopper-generated UR
program using **Custom Command** components.

> **⚠️ v3 (low-latency branch) — re-read before pasting.**
> Canonical source of truth: `urscript/pulsar/lib_pulsar.script` and the
> two READMEs. The v3 model:
> - **One live knob:** `pulsar_set_rate(feed)` — mm/min screw speed =
>   deposition rate. No flow-%, no `M221`, no retract, and the old
>   `pulsar_flow_on/off` aliases are **gone** (use `pulsar_resume` /
>   `pulsar_pause`).
> - **Time-based daemon chunks** (`pulsar_latency`, default 0.25 s) —
>   rate changes and pauses bite in ~constant time at any rate.
> - **UR pause / e-stop stop the extruder in hardware**: a UR DO
>   ("high while program running") wired to Duet `io1.in` gates the
>   daemon directly. Nothing in the GH program handles pause — pausing
>   the robot stops the screw within ~1 chunk, resuming resumes it.
>   (`wait_for_pulsar_enabled` is gone from the library.)
> - **Preheat + purge stay out of the live program** (separate blocking
>   `preheat_purge.script` run beforehand). Setup just connects.
> - **`[F]` values come from calibration**: the DWC calibration macros
>   write `pulsar-flowcal.csv` (grams-per-time at 10 rates) that GH can
>   fetch straight off the Duet — see "Calibration → Grasshopper" below.
> - **PETG defaults:** barrel 215 °C, nozzle 245 °C, feed 600 mm/min.

The GH component has four inputs we care about:

| Input | What it does |
|---|---|
| **Name** | Identifier on the GH canvas. Free-form. |
| **Manufacturer** | `UR`. |
| **Command code** | URScript that gets injected **inline** at the position of this component in the program flow. |
| **Declaration** | URScript that gets injected **at the top of `Program()`**, alongside `pulsarTcp`, `pulsarWeight`, etc. — variables, constants, and function definitions live here. |

### Indentation rule (important)

The GH plugin auto-indents only the **first line** of each Declaration
and Command code field to match the surrounding `Program()` context (2
spaces). Every subsequent line is passed through verbatim. So you must
manually prepend 2 spaces to every line after the first; function
bodies inside a `def ... end` block need 4 spaces. The first line is
the exception — leave it with no leading spaces, GH will indent it.

All the code blocks below are already pre-indented to this rule.
Paste them in as-is.

Four mandatory components cover any print (and are all vase mode needs);
four more are optional for mid-print pauses, layer changes / travels,
and live rate changes. The
operator-facing popups ("Press Ready", "Job Complete", "Pause") live
inside the components that fire at those moments — text and title are
parameterised from GH inputs the same way the temps and feeds are.

---

## Reference output

Compare against `PULSTEST9.urp`. The `movej` calls are GH's existing
output. The `<<<` lines show where each Custom Command injects.

```python
def Program():
  pulsarTcp = p[-0, 0.10674, 0.07506, 0, 2.22144, 2.22144]
  pulsarWeight = 1.6
  pulsarCog = [-0, 0.10674, 0.07506]
  Speed000 = 0.1
  Zone000 = 0.001

  # <<< CC: Pulsar Setup — Declaration block (defs)
  # <<< CC: Pulsar Setup — Command code (connect + handshake, NON-blocking;
  #     preheat + purge were done beforehand by preheat_purge.script)

  set_tcp(pulsarTcp)
  set_payload(pulsarWeight, pulsarCog)
  movej([0.1073, -1.5563, ...], a=3.1416, v=0.3142, r=Zone000)   ; home

  # <<< CC: Pulsar Start — popup + begin extrusion
  movel(...)                                                     ; spiral motion ↓
  ; ... one continuous vase-mode spiral (movel/movej), Z rising ...
  movel(...)                                                     ; last bead point

  # <<< CC: Pulsar Stop — pause screw + stop daemon + cooldown
  movej([0.1073, -1.5563, ...], a=3.1416, v=0.3532, r=Zone000)   ; return home

  # <<< CC: Pulsar End — popup + close socket

end
Program()
```

For **vase mode** this is the whole story: the screw starts at Pulsar
Start and runs uninterrupted through the single continuous spiral until
Pulsar Stop — no layer-change or travel components needed. Pulsar Stop
fires **before** the return-home `movej`, so the screw is already
stopped during the travel home. Pulsar End fires **after**, so the
operator sees the "complete" popup once the robot is safely parked.

---

## Mandatory components

### 1. Pulsar Setup (very start)

The only component with a Declaration block. Loads every helper and
all config constants in one shot.

**Name**: `Pulsar Setup`
**Manufacturer**: `UR`

**Declaration** *(paste as-is — pre-indented per the rule above)*:

Note the `duet_send_m98` helper — it builds the `M98 P"filename" …` line
byte-by-byte using `socket_send_byte(34)` for each `"` character.
Polyscope 5.11 does NOT honour `\"` as an escape inside URScript string
literals (parser closes the string early at the first `\"`), so we
can't embed the quotes with a straight escape sequence.

This block is a **complete, self-contained copy** of the v3 helper
library (`lib_pulsar.script`). The live print program only calls the
non-blocking ones — `pulsar_start_extrusion`, `pulsar_set_rate`,
`pulsar_pause`, `pulsar_resume`, `pulsar_stop_extrusion`,
`pulsar_cooldown`, plus `duet_handshake` / `pulsar_show_temp` /
`pulsar_clear_heater_faults` in Setup. The blocking ones
(`duet_send_m98_and_read`, `pulsar_preheat`, `pulsar_purge`) are
included for parity but are **not used here** — preheat + purge run
once beforehand in the separate `preheat_purge.script`. UR pause /
e-stop needs nothing in this program at all: the hardware gate (UR
"program running" DO → Duet `io1.in`) stops the screw directly.
Paste the whole block.

```
def duet_open(ip, port):
    socket_open(ip, port, "duet")
    sleep(0.2)
  end

  def duet_close():
    socket_close("duet")
  end

  def duet_send_line(line):
    socket_send_line(line, "duet")
  end

  def duet_send_m98(filename, params):
    socket_send_string("M98 P", "duet")
    socket_send_byte(34, "duet")
    socket_send_string("0:/macros/", "duet")
    socket_send_string(filename, "duet")
    socket_send_byte(34, "duet")
    socket_send_string(params, "duet")
    socket_send_byte(10, "duet")
  end

  def duet_send_line_and_read(line, timeout):
    socket_send_line(line, "duet")
    sleep(0.05)
    resp = socket_read_string("duet", "", "", False, timeout)
    return resp
  end

  def duet_send_m98_and_read(filename, params, timeout):
    socket_send_string("M98 P", "duet")
    socket_send_byte(34, "duet")
    socket_send_string("0:/macros/", "duet")
    socket_send_string(filename, "duet")
    socket_send_byte(34, "duet")
    socket_send_string(params, "duet")
    socket_send_byte(10, "duet")
    sleep(0.05)
    resp = socket_read_string("duet", "", "", False, timeout)
    return resp
  end

  def duet_handshake(timeout):
    resp = duet_send_line_and_read("M115", timeout)
    if (resp != ""):
      return True
    end
    return False
  end

  def pulsar_clear_heater_faults():
    duet_send_m98("pulsar_clear_faults.g", "")
    sleep(0.1)
  end

  def pulsar_preheat(barrel, nozzle):
    resp = duet_send_m98_and_read("pulsar_preheat.g", " B" + to_str(barrel) + " N" + to_str(nozzle), 900.0)
    if (resp == ""):
      popup("WARNING: preheat timed out waiting for the Duet. Check heaters, thermistors and M570 config.", title="Debug", warning=True, error=False, blocking=True)
    end
    return resp
  end

  def pulsar_show_temp():
    resp = duet_send_line_and_read("M105", 2.0)
    popup("Temp:" + resp, title="Pulsar", warning=False, error=False, blocking=True)
  end

  def pulsar_purge(mm, feed):
    duet_send_m98_and_read("pulsar_purge.g", " E" + to_str(mm) + " F" + to_str(feed), 300.0)
  end

  def pulsar_start_extrusion(feed):
    duet_send_m98("pulsar_start.g", " F" + to_str(feed))
  end

  # Live control — set Duet globals directly, fire-and-forget. Immediate
  # (meta-command, not queued motion), picked up within ~pulsar_latency s.
  def pulsar_set_rate(feed):
    duet_send_line("set global.pulsar_feed = " + to_str(feed))
  end

  def pulsar_pause():
    duet_send_line("set global.pulsar_running = false")
  end

  def pulsar_resume():
    duet_send_line("set global.pulsar_running = true")
  end

  def pulsar_stop_extrusion():
    duet_send_m98("pulsar_stop.g", "")
  end

  def pulsar_cooldown():
    duet_send_m98("pulsar_cooldown.g", "")
  end
```

**Command code**:

```
duet_open("172.22.22.100", 23)
  if (duet_handshake(2.0) == False):
    popup("ERROR: Duet did not respond. Run preheat_purge first. Aborting.", title="Fatal", warning=False, error=True, blocking=True)
    halt
  end
  pulsar_clear_heater_faults()
  pulsar_show_temp()
```

Setup **no longer preheats** — the operator runs `preheat_purge.script`
once beforehand, so both zones are already at temp and the screw is
primed. Setup opens the socket, fails loud if the Duet is unreachable,
clears any latched heater fault, and pops the current `M105` reading so
the operator can eyeball that the zones really are at 215/245 before
starting. The `M105` read has a 2 s timeout — none of this blocks the
program for more than a moment. (Drop `pulsar_show_temp()` if you don't
want the extra popup on the demo floor.)

---

### 2. Pulsar Start (before first print move)

Pop the operator gate, then start the daemon. Preheat + purge already
happened (separate routine), so there's nothing to wait on — just the
final "I've checked the machine" human checkpoint before the screw
starts turning.

**Name**: `Pulsar Start`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
popup("Press Ready to start your print", title="Operator_Safety", warning=False, error=False, blocking=True)
  pulsar_start_extrusion(600)
```

To change the rate live during the print, call `pulsar_set_rate(<feed>)`
from a Rate component (below). UR pause / e-stop needs nothing here —
the hardware gate stops the screw directly.

| Substitute in | Default | Purpose |
|---|---|---|
| `Press Ready to start your print` | — | Popup message text |
| `Operator_Safety` | — | Popup title |
| `600` | — | Screw F-value / start rate (mm/min) |

---

### 3. Pulsar Stop (after last print move, BEFORE the return-home `movej`)

Halts the screw, clears the daemon flag, releases the motor, kills the
heaters. No retract (inert on a screw), no popup — the robot can travel
home with the extruder already shut down.

**Name**: `Pulsar Stop`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
pulsar_pause()
  pulsar_stop_extrusion()
  pulsar_cooldown()
```

`pulsar_pause()` halts the screw within ~one chunk so nothing extrudes
during the home move; `pulsar_stop_extrusion()` then releases the motor
and `pulsar_cooldown()` turns the heaters off.

---

### 4. Pulsar End (after the return-home `movej`)

Operator popup, then close the socket. Robot is already parked at this
point, so the operator can safely tidy up.

**Name**: `Pulsar End`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
popup("Job Complete! Please put all the caps back on the pens and tidy up!", title="Job_Done", warning=False, error=False, blocking=True)
  duet_close()
```

| Substitute in | Default | Purpose |
|---|---|---|
| `Job Complete!...` | — | Popup message text |
| `Job_Done` | — | Popup title |

---

## Optional components

### 5. Pulsar Pause (anywhere mid-print)

Scripted pause for hardware insertion / inspection / interventions.
`pulsar_pause()` stops the daemon feeding chunks, so the screw halts
within ~one chunk; the popup blocks; `pulsar_resume()` restarts the
screw at the current rate when the operator clicks OK. No retract — on
a screw the melt volume swallows it; stopping the screw breaks the bead.

**Name**: `Pulsar Pause`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
pulsar_pause()
  popup("Insert hardware now. Click OK to resume.", title="Pause", warning=False, error=False, blocking=True)
  pulsar_resume()
```

| Substitute in | Default | Purpose |
|---|---|---|
| `Insert hardware now...` | — | Popup message text |
| `Pause` | — | Popup title |

---

### 6. Pulsar Pre-Travel (before each travel `movej`)

```
pulsar_pause()
```

### 7. Pulsar Post-Travel (after each travel `movej`)

```
pulsar_resume()
```

### 8. Pulsar Flow / rate change (anywhere mid-print)

Set the live deposition rate (screw speed, mm/min). Takes effect within
~one chunk. This replaces the old flow-% component.

```
pulsar_set_rate(450)
```

---

## Minimum viable first GH test (vase mode)

Build only the four mandatory components: **Setup, Start, Stop, End**.
Vase mode is the ideal first demo because it's a **single continuous
spiral** — the screw runs uninterrupted from Pulsar Start to Pulsar
Stop, so none of the timing-sensitive components (Pause, Layer-Change,
Travel, Flow) are involved and daemon latency is irrelevant.

Order of operations end to end:

1. Run `preheat_purge.script` on the pendant, once. Wait for "Ready".
2. Run the GH-generated program: **Setup** connects + confirms temp →
   home → **Start** (operator Ready popup, screw on) → the spiral →
   **Stop** (screw off) → return home → **End** (done popup, socket
   closed).

Tune the bead with a single number — `pulsar_start_extrusion(<feed>)`
in Start — against your spiral's XY speed and layer height. If you want
to change rate mid-spiral later, add a **Flow** component
(`pulsar_set_rate`), but you don't need it for a first vase.

## Parameterising from Grasshopper

Note: `barrel` / `nozzle` temps now live in `preheat_purge.script`
(run once beforehand), NOT in a GH component — Setup no longer preheats.

| Parameter | Default | Component | Why |
|---|---|---|---|
| Duet IP | `172.22.22.100` | Setup | Could change per network |
| `feed` (F-value) | 600 | Start | Start rate; screw speed = deposition rate |
| Live rate `feed` | 450 | Flow | Mid-print rate change (`pulsar_set_rate`) |
| Start popup text/title | — | Start | Per-print operator notes |
| End popup text/title | — | End | Per-print operator notes |
| Pause popup text/title | — | Pause | Per-pause instructions |

Strings (popup text, title) need to be quoted in the URScript output
— same as today. Pipe them in the same way you pipe the numeric
inputs.

## Placeholder-substitution versions

If your GH definition uses find-and-replace tokens to inject values
into Custom Command fields, here are the same blocks with our standard
placeholders pre-wired:

| Placeholder | Maps to |
|---|---|
| `[Popup]` | Popup message text |
| `[F]` | Feed / rate (mm/min = screw speed) |

### Setup — Command code

```
duet_open("172.22.22.100", 23)
  if (duet_handshake(2.0) == False):
    popup("ERROR: Duet did not respond. Run preheat_purge first. Aborting.", title="Fatal", warning=False, error=True, blocking=True)
    halt
  end
  pulsar_clear_heater_faults()
  pulsar_show_temp()
```

### Start — Command code

```
popup("[Popup]", title="Operator_Safety", warning=False, error=False, blocking=True)
  pulsar_start_extrusion([F])
```

### Stop — Command code

```
pulsar_pause()
  pulsar_stop_extrusion()
  pulsar_cooldown()
```

### End — Command code

```
popup("[Popup]", title="Job_Done", warning=False, error=False, blocking=True)
  duet_close()
```

### Pause — Command code

```
pulsar_pause()
  popup("[Popup]", title="Pause", warning=False, error=False, blocking=True)
  pulsar_resume()
```

### Pre-Travel — Command code

```
pulsar_pause()
```

### Post-Travel — Command code

```
pulsar_resume()
```

### Flow / rate — Command code

```
pulsar_set_rate([F])
```

The `"172.22.22.100"` (Duet IP) isn't templated — add an `[IP]`
placeholder to taste if you want to parameterise it too.

## UR pause / e-stop → extruder stop (hardware gate)

Nothing in the GH program handles robot pause. A UR digital output,
configured in **Installation → I/O Setup** with the action **"High when
program is running"**, is wired to the Duet's `io1.in` (+ common 0V).
`daemon.g` requires that pin to read 1 (when `global.pulsar_hw_gate` is
true), so:

- **Pause** the UR → DO drops → screw stops within ~1 chunk (~0.25 s).
- **E-stop** the UR → all UR outputs drop → same stop, no software
  involved at all.
- **Resume** → DO high → screw resumes at the current rate
  automatically.
- Broken/unplugged wire reads low → extruder stops → fail-safe.

Until the wire is in, leave `pulsar_hw_gate = false` (the default) in
`pulsar_init.g` and everything works as before. Full wiring detail in
`/duet/README.md`.

## Calibration → Grasshopper ([F] values from real data)

The DWC calibration macros (`macros/calibration/` on the Duet) produce
CSVs on the SD card that GH can fetch straight off the printer:

| File | Content | URL |
|---|---|---|
| `pulsar-temps.csv` | material, barrel, nozzle | `http://<ip>/rr_download?name=/sys/pulsar-temps.csv` |
| `pulsar-limits.csv` | material, min feed, max feed, temps | `http://<ip>/rr_download?name=/sys/pulsar-limits.csv` |
| `pulsar-flowcal.csv` | material, feed, seconds, grams, g/min, mm³/s | `http://<ip>/rr_download?name=/sys/pulsar-flowcal.csv` |

In GH, fetch the flow-cal CSV (Swiftlet's HTTP GET, a one-line C#
`WebClient.DownloadString`, or manually download via DWC → System and
read the file). Interpolate the feed→mm³/s curve to pick the `[F]` that
delivers your target volumetric flow (layer height × bead width × robot
speed), instead of guessing from steps/mm.

## EXPERIMENTAL — pendant speed slider drives extrusion (autorate)

`urscript/pulsar/autorate_thread.script` is an optional URScript thread
that polls the robot's *actual* TCP speed ~7×/s and pushes a matching
feed to the Duet (`feed = k × speed`). With it running, dragging the
pendant speed slider — or the robot's own accel/decel — automatically
modulates deposition. Paste its defs into the Setup Declaration, start
it right after `pulsar_start_extrusion(...)` with `thrd = run
pulsar_autorate()`, and `kill thrd` before Pulsar Stop. Follow lag is
~0.3–0.5 s, so it's for slider moves and gentle ramps — not sharp
corners (keep blend radii doing that). Calibrate `pulsar_k` as
`F_nominal / v_nominal` (e.g. 600 / 0.035 ≈ 17143).
