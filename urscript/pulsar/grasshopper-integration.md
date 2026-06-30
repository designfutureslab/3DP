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
  # <<< CC: Pulsar Setup — Command code (connect + preheat)

  set_tcp(pulsarTcp)
  set_payload(pulsarWeight, pulsarCog)
  movej([0.1073, -1.5563, ...], a=3.1416, v=0.3142, r=Zone000)   ; home

  # <<< CC: Pulsar Start — wait + popup + begin extrusion
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

### 2. Pulsar Start (before first print move)

Wait for the Pulsar ready signal (no-op in debug, DIO poll in
production), pop the operator gate, then start the daemon.

**Name**: `Pulsar Start`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
wait_for_pulsar_enabled(debug_pulsar_ready, pulsar_ready_pin)
popup("Press Ready to start your print", title="Operator_Safety", warning=False, error=False, blocking=True)
pulsar_start_extrusion(900, 100)
```

| Substitute in | Default | Purpose |
|---|---|---|
| `Press Ready to start your print` | — | Popup message text |
| `Operator_Safety` | — | Popup title |
| `900` | — | Screw F-value (mm/min) |
| `100` | — | Initial flow % |

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
pulsar_flow_off()
pulsar_retract(3.0, 600)
pulsar_stop_extrusion()
pulsar_cooldown()
```

| Substitute in | Default | Purpose |
|---|---|---|
| `3.0` | — | Retract distance (mm) |
| `600` | — | Retract feedrate (mm/min) |

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
Stops the bead, retracts, blocks on a popup, then unretracts and
resumes flow when the operator clicks OK. The screw stays parked
while the popup is showing because `M221 S0` pins the multiplier at
zero even though the daemon keeps queueing chunks.

**Name**: `Pulsar Pause`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
pulsar_flow_off()
pulsar_retract(3.0, 600)
popup("Insert hardware now. Click OK to resume.", title="Pause", warning=False, error=False, blocking=True)
pulsar_unretract(3.0, 600)
pulsar_flow_on(100)
```

| Substitute in | Default | Purpose |
|---|---|---|
| `3.0` | — | Retract distance (mm) |
| `600` | — | Retract feedrate (mm/min) |
| `Insert hardware now...` | — | Popup message text |
| `Pause` | — | Popup title |
| `100` | — | Flow % to resume at (match the active layer's flow) |

---

### 6. Pulsar Pre-Travel (before each travel `movej`)

```
pulsar_flow_off()
pulsar_retract(3.0, 600)
```

### 7. Pulsar Post-Travel (after each travel `movej`)

```
pulsar_unretract(3.0, 600)
pulsar_flow_on(100)
```

### 8. Pulsar Flow (anywhere mid-print)

```
pulsar_flow_on(75)
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

| Parameter | Default | Component | Why |
|---|---|---|---|
| `barrel` temp | 190 | Setup | Material switch (PLA vs PETG) |
| `nozzle` temp | 215 | Setup | Material switch |
| Duet IP | `172.22.22.100` | Setup | Could change per network |
| `feed` (F-value) | 900 | Start | Volumetric calibration |
| `flow` initial % | 100 | Start | Bead width tuning |
| Start popup text/title | — | Start | Per-print operator notes |
| `retract` mm | 3.0 | Stop / Pause / Travel | Material-specific |
| `retract` feed | 600 | Stop / Pause / Travel | Material-specific |
| End popup text/title | — | End | Per-print operator notes |
| Pause popup text/title | — | Pause | Per-pause instructions |
| Resume flow % | 100 | Pause | Match active layer flow |

Strings (popup text, title) need to be quoted in the URScript output
— same as today. Pipe them in the same way you pipe the numeric
inputs.

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
