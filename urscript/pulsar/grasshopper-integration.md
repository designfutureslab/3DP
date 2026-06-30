# Pulsar control via Grasshopper Custom Commands

How to weave Pulsar extrusion control into a Grasshopper-generated UR
program using **Custom Command** components.

The GH component has four inputs we care about:

| Input | What it does |
|---|---|
| **Name** | Identifier on the GH canvas. Free-form. |
| **Manufacturer** | `UR`. |
| **Command code** | URScript that gets injected **inline** at the position of this component in the program flow. |
| **Declaration** | URScript that gets injected **at the top of `Program()`**, alongside `pulsarTcp`, `pulsarWeight`, etc. — variables, constants, and function definitions live here. |

Three components cover any print. The operator popups that used to be
their own GH `Popup` components are now folded into **Pulsar Start**
(the "Press Ready" gate) and **Pulsar End** (the "Job Complete"
notice) — the popup text stays parameterised from GH inputs the same
way the temperatures and feeds do.

---

## Reference output

Compare against `PULSTEST9.urp` — the `movej` calls are GH's existing
output. The `<<<` lines show where each Custom Command injects.

```python
def Program():
  pulsarTcp = p[-0, 0.10674, 0.07506, 0, 2.22144, 2.22144]
  pulsarWeight = 1.6
  pulsarCog = [-0, 0.10674, 0.07506]
  Speed000 = 0.1
  Zone000 = 0.001

  # <<< CC: Pulsar Setup — Declaration block:
  debug_pulsar_ready = True
  pulsar_ready_pin   = 0
  def duet_open(ip, port): ... end
  def duet_close(): ... end
  def duet_send_line(line): ... end
  def duet_send_line_and_read(line, timeout): ... end
  def duet_handshake(timeout): ... end
  def pulsar_clear_heater_faults(): ... end
  def pulsar_preheat(barrel, nozzle): ... end
  def wait_for_pulsar_enabled(debug, pin): ... end
  def pulsar_start_extrusion(feed, flow): ... end
  def pulsar_flow_on(flow): ... end
  def pulsar_flow_off(): ... end
  def pulsar_retract(mm, feed): ... end
  def pulsar_unretract(mm, feed): ... end
  def pulsar_stop_extrusion(): ... end
  def pulsar_cooldown(): ... end

  set_tcp(pulsarTcp)
  set_payload(pulsarWeight, pulsarCog)

  # <<< CC: Pulsar Setup — Command code:
  duet_open("172.22.22.100", 23)
  pulsar_clear_heater_faults()
  pulsar_preheat(190, 215)

  movej([0.1073, -1.5563, ...], a=3.1416, v=0.3142, r=Zone000)   ; home

  # <<< CC: Pulsar Start — wait + operator popup + begin extrusion:
  wait_for_pulsar_enabled(debug_pulsar_ready, pulsar_ready_pin)
  popup("Press Ready to start your print", title="Operator_Safety", warning=False, error=False, blocking=True)
  pulsar_start_extrusion(900, 100)

  movej([0.1918, -1.9656, ...], a=3.1416, v=0.3716, r=Zone000)   ; print motion ↓
  movej([...], ...)
  ; ... many movej commands ...
  movej([0.2424, -1.9481, ...], a=3.1416, v=0.2829, r=Zone000)   ; last bead point

  # <<< CC: Pulsar End — stop, cool, popup, close socket:
  pulsar_flow_off()
  pulsar_retract(3.0, 600)
  pulsar_stop_extrusion()
  pulsar_cooldown()
  popup("Job Complete! Please put all the caps back on the pens and tidy up!", title="Job_Done", warning=False, error=False, blocking=True)
  duet_close()

  movej([0.1073, -1.5563, ...], a=3.1416, v=0.3532, r=Zone000)   ; return home

end
Program()
```

The operator clicks OK on **Pulsar Start**'s popup → screw begins.
They click OK on **Pulsar End**'s popup → socket closes → robot
returns home. No separate `Popup` components needed for the operator
gates.

---

## The components

### 1. Pulsar Setup (mandatory — very start)

The only component with a Declaration block. Loads every helper and
all config constants in one shot.

**Name**: `Pulsar Setup`
**Manufacturer**: `UR`

**Declaration** *(paste as-is)*:

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

def duet_send_line_and_read(line, timeout):
  socket_send_line(line, "duet")
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
  duet_send_line("M98 P\"pulsar_clear_faults.g\"")
  sleep(0.1)
end

def pulsar_preheat(barrel, nozzle):
  cmd = "M98 P\"pulsar_preheat.g\" B" + to_str(barrel) + " N" + to_str(nozzle)
  duet_send_line(cmd)
end

def wait_for_pulsar_enabled(debug, pin):
  if (debug == False):
    while (get_standard_digital_in(pin) == False):
      sleep(0.5)
    end
  end
end

def pulsar_start_extrusion(feed, flow):
  cmd = "M98 P\"pulsar_start.g\" F" + to_str(feed) + " R" + to_str(flow)
  duet_send_line(cmd)
end

def pulsar_flow_on(flow):
  duet_send_line("M98 P\"pulsar_flow.g\" S" + to_str(flow))
end

def pulsar_flow_off():
  duet_send_line("M98 P\"pulsar_flow.g\" S0")
end

def pulsar_retract(mm, feed):
  duet_send_line("M98 P\"pulsar_retract.g\" S" + to_str(mm) + " F" + to_str(feed))
end

def pulsar_unretract(mm, feed):
  duet_send_line("M98 P\"pulsar_unretract.g\" S" + to_str(mm) + " F" + to_str(feed))
end

def pulsar_stop_extrusion():
  duet_send_line("M98 P\"pulsar_stop.g\"")
end

def pulsar_cooldown():
  duet_send_line("M98 P\"pulsar_cooldown.g\"")
end
```

**Command code**:

```
duet_open("172.22.22.100", 23)
pulsar_clear_heater_faults()
pulsar_preheat(190, 215)
```

Wire `190` and `215` to GH inputs for barrel/nozzle temps.

---

### 2. Pulsar Start (mandatory — before first print move)

Three lines, one component:

1. **Wait** for the Pulsar ready signal (no-op in debug, DIO poll in production).
2. **Operator popup** — final go gate, text parameterised from GH.
3. **Start the daemon** — screw begins turning once the operator clicks OK.

**Name**: `Pulsar Start`
**Manufacturer**: `UR`
**Declaration**: *(empty — Setup did the work)*

**Command code**:

```
wait_for_pulsar_enabled(debug_pulsar_ready, pulsar_ready_pin)
popup("Press Ready to start your print", title="Operator_Safety", warning=False, error=False, blocking=True)
pulsar_start_extrusion(900, 100)
```

Wire from GH:

| Substitute in | Default in example | Purpose |
|---|---|---|
| `Press Ready to start your print` | — | Popup message text |
| `Operator_Safety` | — | Popup title |
| `900` | — | Screw F-value (mm/min) |
| `100` | — | Initial flow % |

---

### 3. Pulsar End (mandatory — after last print move, before any return-home move)

Stop the bead instantly, retract, clear the daemon flag, kill the
heaters, prompt the operator, then close the socket. The operator
clicks OK to acknowledge → socket closes → GH's return-home `movej`
runs next. Since flow is off and the daemon is stopped, no material
comes out during the return travel even if a queued chunk is still
draining.

**Name**: `Pulsar End`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
pulsar_flow_off()
pulsar_retract(3.0, 600)
pulsar_stop_extrusion()
pulsar_cooldown()
popup("Job Complete! Please put all the caps back on the pens and tidy up!", title="Job_Done", warning=False, error=False, blocking=True)
duet_close()
```

Wire from GH:

| Substitute in | Default in example | Purpose |
|---|---|---|
| `3.0` | — | Retract distance (mm) |
| `600` | — | Retract feedrate (mm/min) |
| `Job Complete!...` | — | Popup message text |
| `Job_Done` | — | Popup title |

---

## Optional components

### 4. Pulsar Pre-Travel (before each travel `movej`)

Pause bead and retract.

**Command code**:

```
pulsar_flow_off()
pulsar_retract(3.0, 600)
```

### 5. Pulsar Post-Travel (after each travel `movej`)

Unretract and resume flow.

**Command code**:

```
pulsar_unretract(3.0, 600)
pulsar_flow_on(100)
```

### 6. Pulsar Flow (anywhere mid-print)

Bump or trim flow %. No retract.

**Command code**:

```
pulsar_flow_on(75)
```

---

## Minimum viable first GH test

For your first print test, you only need the **three mandatory
components**: Setup, Start, End. Skip Pre-Travel / Post-Travel / Flow
until you're doing multi-layer prints with travels.

For a single-layer continuous bead, the screw just runs from Pulsar
Start to Pulsar End. No retracts needed mid-print.

## Parameterising from Grasshopper

Numbers you'll likely want hooked to GH inputs:

| Parameter | Default | Component | Why |
|---|---|---|---|
| `barrel` temp | 190 | Setup | Material switch (PLA vs PETG) |
| `nozzle` temp | 215 | Setup | Material switch |
| Duet IP | `172.22.22.100` | Setup | Could change per network |
| `feed` (F-value) | 900 | Start | Volumetric calibration |
| `flow` initial % | 100 | Start | Bead width tuning |
| Start popup text | — | Start | Per-print operator notes |
| Start popup title | — | Start | Per-print operator notes |
| `retract` mm | 3.0 | End / Pre/Post-Travel | Material-specific |
| `retract` feed | 600 | End / Pre/Post-Travel | Material-specific |
| End popup text | — | End | Per-print operator notes |
| End popup title | — | End | Per-print operator notes |

Strings (popup text, title) need to be quoted in the URScript output
— same as today. Pipe them in the same way you pipe the numeric
inputs into the temp / feed fields.

## Switching to production (DIO wired)

Two edits in **Pulsar Setup's Declaration**:

```
debug_pulsar_ready = False     ; was True
pulsar_ready_pin   = 0         ; whichever UR input you used
```

Nothing else changes on the UR side. The Duet's
`pulsar_signal_ready.g` and `pulsar_signal_clear.g` macros need their
`M42` lines uncommented with the matching Duet output pin — that's the
hardware-side switch.

Once production-wired, **Pulsar Start**'s `wait_for_pulsar_enabled`
call blocks silently until the Duet asserts the ready DIO, and *only
then* does the popup appear. The operator no longer has to monitor
DWC; the script gates itself on the wire, then asks the operator to
acknowledge.
