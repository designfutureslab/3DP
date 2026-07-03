# Pulsar control via Grasshopper Custom Commands

How to weave Pulsar extrusion control into a Grasshopper-generated UR
program using **Custom Command** components.

> **⚠️ Updated for the responsiveness redesign — re-read before pasting.**
> The model changed materially. The code blocks below have been updated
> to match, but the canonical source of truth is
> `urscript/pulsar/lib_pulsar.script` (functions) and the two READMEs.
> What changed:
> - **Preheat + purge moved out of the live program** into a separate,
>   blocking `preheat_purge.script` the operator runs once beforehand.
>   **Pulsar Setup no longer preheats** — it just connects. The live
>   program never blocks.
> - **Live control is via Duet globals**, not `M221`:
>   `pulsar_set_rate(feed)` (rate), `pulsar_pause()` / `pulsar_resume()`.
>   Screw speed *is* the flow — there's no flow-% multiplier any more.
>   `pulsar_flow_off()` / `pulsar_flow_on()` remain as aliases → pause /
>   resume.
> - **No retract** in the pause / layer-change / travel flows (inert on a
>   screw). `pulsar_start_extrusion(feed)` dropped its flow argument.
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

Four mandatory components cover any print; four more are optional for
mid-print pauses, layer-change retraction, and flow trim. The
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

  # <<< CC: Pulsar Setup — Declaration block (defs + flags)
  # <<< CC: Pulsar Setup — Command code (connect + preheat, BLOCKING —
  #     this step doesn't return until the Duet confirms both zones
  #     are at temp, so the next line of the program only runs once
  #     preheat genuinely finishes)

  set_tcp(pulsarTcp)
  set_payload(pulsarWeight, pulsarCog)
  movej([0.1073, -1.5563, ...], a=3.1416, v=0.3142, r=Zone000)   ; home

  # <<< CC: Pulsar Start — popup + begin extrusion
  movej([0.1918, -1.9656, ...], a=3.1416, v=0.3716, r=Zone000)   ; print motion ↓
  ; ... many movej commands ...
  movej([0.2424, -1.9481, ...], a=3.1416, v=0.2829, r=Zone000)   ; last bead point

  # <<< CC: Pulsar Stop — flow off + retract + stop daemon + cooldown
  movej([0.1073, -1.5563, ...], a=3.1416, v=0.3532, r=Zone000)   ; return home

  # <<< CC: Pulsar End — popup + close socket

end
Program()
```

Pulsar Stop fires **before** the return-home `movej`, so the bead is
already off and the daemon has stopped queueing chunks during the
travel. Pulsar End fires **after**, so the operator sees the
"complete" popup once the robot is safely parked.

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

There's a second variant, `duet_send_m98_and_read`, used only by
`pulsar_preheat`. RRF doesn't send its Telnet "ok" reply until the
whole macro file — including any blocking command inside it, like
`pulsar_preheat.g`'s `M116` — has finished. So blocking on that socket
read is how `pulsar_preheat()` waits for both zones to genuinely reach
temperature, with no polling and no operator judgement call about
whether DWC "looks close enough". Timeout is 15 minutes; if it fires,
something is actually wrong (heater fault, thermistor fault, etc.) and
`pulsar_preheat()` pops a warning.

```
debug_pulsar_ready = True
  pulsar_ready_pin   = 0

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
    popup("Temp:" + resp, title="Debug", warning=False, error=False, blocking=True)
  end

  # Reserved for future Duet->UR safety signalling (e-stop / pause)
  # once a DIO line is wired between the two boards. Not used for
  # temperature gating any more — pulsar_preheat() blocks on its own.
  def wait_for_pulsar_enabled(debug, pin):
    if (debug == False):
      while (get_standard_digital_in(pin) == False):
        sleep(0.5)
      end
    end
  end

  def pulsar_start_extrusion(feed):
    duet_send_m98("pulsar_start.g", " F" + to_str(feed))
  end

  # Live control — set Duet globals directly, fire-and-forget. Immediate
  # (meta-command, not queued motion), picked up within ~1 chunk.
  def pulsar_set_rate(feed):
    duet_send_line("set global.pulsar_feed = " + to_str(feed))
  end

  def pulsar_pause():
    duet_send_line("set global.pulsar_running = false")
  end

  def pulsar_resume():
    duet_send_line("set global.pulsar_running = true")
  end

  # Legacy aliases — flow % is no longer meaningful (rate = screw speed);
  # these now just pause / resume. Prefer pulsar_pause/resume/set_rate.
  def pulsar_flow_off():
    pulsar_pause()
  end

  def pulsar_flow_on(flow):
    pulsar_resume()
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
```

Setup **no longer preheats** — the operator runs `preheat_purge.script`
once beforehand, so both zones are already at temp and the screw is
primed. Setup just opens the socket and does a quick handshake so an
unreachable Duet fails loud instead of silently. Nothing here blocks.

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
from a Flow component (below). `wait_for_pulsar_enabled(...)` is still
defined in Setup's Declaration but not called — add it back if/when a
future Duet→UR safety signal is wired up.

| Substitute in | Default | Purpose |
|---|---|---|
| `Press Ready to start your print` | — | Popup message text |
| `Operator_Safety` | — | Popup title |
| `600` | — | Screw F-value / start rate (mm/min) |

---

### 3. Pulsar Stop (after last print move, BEFORE the return-home `movej`)

Stops the bead instantly, retracts, clears the daemon flag, kills the
heaters. No popup — the robot can travel home with the extruder
already shut down.

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

## Minimum viable first GH test

Build the four mandatory components: **Setup, Start, Stop, End**. Skip
everything else until you're doing multi-layer prints with travels or
need a scripted pause.

For a single-layer continuous bead, the screw runs uninterrupted from
Pulsar Start to Pulsar Stop. Then the robot returns home. Then Pulsar
End fires the operator popup and closes the socket.

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

## Note on the Duet→UR ready DIO

Earlier revisions of this doc used a `debug_pulsar_ready` /
`pulsar_ready_pin` pair to gate on a Duet→UR hardware signal for
"heaters at temp". That's no longer needed for temperature — the
operator runs `preheat_purge.script` first, and `pulsar_preheat()`
there blocks on the socket reply itself until both zones are at temp,
so the heaters are already ready before the live program ever runs.

The `wait_for_pulsar_enabled(debug, pin)` function is kept in the
Declaration purely as a placeholder for a *different* future use: a
Duet→UR safety signal (e-stop / pause) that would need its own wiring
and its own Duet-side macro logic, separate from
`pulsar_signal_ready.g` / `pulsar_signal_clear.g`. Don't wire those
existing signal macros up expecting them to gate temperature — that
job is already done.
