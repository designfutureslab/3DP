# Pulsar control via Grasshopper Custom Commands

How to weave Pulsar extrusion control into a Grasshopper-generated UR
program using **Custom Command** components.

The GH component has four inputs we care about:

| Input | What it does |
|---|---|
| **Name** | Identifier shown in the GH canvas. Free-form. |
| **Manufacturer** | `UR`. |
| **Command code** | URScript that gets injected **inline** at the position of this component in the program flow. |
| **Declaration** | URScript that gets injected **at the top of `Program()`**, alongside `pulsarTcp`, `pulsarWeight`, etc. — variables, constants, and function definitions live here. |

You'll set up six components total. Three are essential for any print;
three more are for layer-change retraction / mid-print flow tweaks.

---

## Reference output

This is what the final program looks like after all the Custom Commands
have fired. Lines marked `<<< CC: <name>` show where each component
injects code. Compare against `PULSTEST9.urp` — the `movej` calls are
identical to GH's output, the `<<<` lines are what each Custom Command
adds.

```python
def Program():
  pulsarTcp = p[-0, 0.10674, 0.07506, 0, 2.22144, 2.22144]
  pulsarWeight = 1.6
  pulsarCog = [-0, 0.10674, 0.07506]
  Speed000 = 0.1
  Zone000 = 0.001

  # <<< CC: Pulsar Setup — its Declaration block goes here:
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

  # <<< CC: Pulsar Setup — its Command code goes here:
  duet_open("172.22.22.100", 23)
  pulsar_clear_heater_faults()
  pulsar_preheat(190, 215)

  movej([0.1073, -1.5563, ...], a=3.1416, v=0.3142, r=Zone000)   ; home

  # <<< CC: Pulsar Ready — blocks on DIO in production, no-op in debug
  wait_for_pulsar_enabled(debug_pulsar_ready, pulsar_ready_pin)

  # Existing GH popup — the operator's "click to start" gate
  popup("Press Ready to start your print", title="Operator_Safety", warning=False, error=False, blocking=True)

  # <<< CC: Pulsar Start — begin continuous extrusion
  pulsar_start_extrusion(900, 100)

  movej([0.1918, -1.9656, ...], a=3.1416, v=0.3716, r=Zone000)   ; print motion ↓
  movej([...], ...)
  movej([...], ...)
  ; ... many movej commands ...
  movej([0.2424, -1.9481, ...], a=3.1416, v=0.2829, r=Zone000)   ; last bead point

  # <<< CC: Pulsar End — stop extrusion, cool down, drop ready signal
  pulsar_stop_extrusion()
  pulsar_cooldown()

  movej([0.1073, -1.5563, ...], a=3.1416, v=0.3532, r=Zone000)   ; return home

  # <<< CC: Pulsar Disconnect — close the socket
  duet_close()

  # Existing GH popup — end message
  popup("Job Complete! Please put all the caps back on the pens and tidy up!", title="Job_Done", warning=False, error=False, blocking=True)

end
Program()
```

---

## The components

### 1. Pulsar Setup (mandatory, place at the very start)

This is the only component with a Declaration block — it loads every
helper function the rest of the components rely on, plus the debug-mode
constants.

**Name**: `Pulsar Setup`
**Manufacturer**: `UR`

**Declaration** *(paste as-is — these are the function library)*:

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

**Command code** *(connect, clear faults, fire preheat)*:

```
duet_open("172.22.22.100", 23)
pulsar_clear_heater_faults()
pulsar_preheat(190, 215)
```

Swap the `190, 215` values from GH inputs so the temps are
parameterised (PLA = 190/215, PETG = ~220/245).

---

### 2. Pulsar Ready (mandatory, place just before your "Press Ready" popup)

Holds the script until the Duet's ready DIO goes high. In debug mode
(`debug_pulsar_ready = True` from Setup), this is a no-op — the
operator gates the start by waiting to click your "Press Ready" popup.

**Name**: `Pulsar Ready`
**Manufacturer**: `UR`
**Declaration**: *(empty — Setup already did the work)*

**Command code**:

```
wait_for_pulsar_enabled(debug_pulsar_ready, pulsar_ready_pin)
```

---

### 3. Pulsar Start (mandatory, place after the "Press Ready" popup, before first print move)

Fires the Duet daemon. Once this command executes, the screw is
turning. Place it **after** the operator popup so the screw doesn't
start spinning while the operator is still standing next to the
machine.

**Name**: `Pulsar Start`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
pulsar_start_extrusion(900, 100)
```

`900` is the screw F-value (mm/min). `100` is the initial flow %. Pipe
these from GH inputs.

---

### 4. Pulsar End (mandatory, place after the last bead move, before the return-to-home move)

Stops the screw and cools the heaters. Place it at the end of motion
but BEFORE the move-home travel — you want the bead to stop at the
last printed point, not while travelling away.

**Name**: `Pulsar End`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
pulsar_stop_extrusion()
pulsar_cooldown()
```

---

### 5. Pulsar Disconnect (mandatory, place at the very end, after the "Job Complete" popup)

Closes the socket. Cheap; mostly hygiene.

**Name**: `Pulsar Disconnect`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
duet_close()
```

---

### 6. Pulsar Layer Change — Pre-Travel (optional, place before each travel `movej`)

Pause the bead and retract before lifting / travelling to the next
layer start.

**Name**: `Pulsar Pre-Travel`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
pulsar_flow_off()
pulsar_retract(3.0, 600)
```

---

### 7. Pulsar Layer Change — Post-Travel (optional, place after each travel `movej`)

Unretract and resume flow once the head is back at the next layer's
start point.

**Name**: `Pulsar Post-Travel`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
pulsar_unretract(3.0, 600)
pulsar_flow_on(100)
```

---

### 8. Pulsar Flow (optional, anywhere mid-print)

Single-line flow tweak, no retract. Use for slowing the bead on
overhangs or speeding up on infill — purely a multiplier on the
underlying screw speed.

**Name**: `Pulsar Flow`
**Manufacturer**: `UR`
**Declaration**: *(empty)*

**Command code**:

```
pulsar_flow_on(75)
```

Pipe the percentage from a GH input.

---

## Minimum viable first GH test

For your first print test, you only need **five** components:

1. **Pulsar Setup** — at the very start
2. **Pulsar Ready** — just before "Press Ready" popup
3. **Pulsar Start** — just after "Press Ready" popup
4. **Pulsar End** — after the last bead move
5. **Pulsar Disconnect** — at the very end

Skip the layer-change components until you're doing real multi-layer
prints with travels. For a single-layer test bead, the screw just runs
continuously start-to-finish.

## Parameterising from Grasshopper

The numbers you'll most likely want hooked to GH inputs:

| Parameter | Default | Component | Why |
|---|---|---|---|
| `barrel` temp | 190 | Setup | Material switch (PLA vs PETG) |
| `nozzle` temp | 215 | Setup | Material switch |
| Duet IP | `172.22.22.100` | Setup | Could change per network |
| `feed` (F-value) | 900 | Start | Volumetric calibration |
| `flow` initial % | 100 | Start | Bead width tuning |
| `retract` mm | 3.0 | Pre/Post-Travel | Material-specific |
| `retract` feed | 600 | Pre/Post-Travel | Material-specific |

The Custom Command's Command code field accepts standard GH string
interpolation — wire numeric inputs from elsewhere in your definition
straight into the text and they'll appear as literal numbers in the
output.

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
