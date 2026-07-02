; 05_Jog_Extrude.g
; -----------------------------------------------------------------------------
; Constant-speed extrusion jog. Prompts for a speed (and a run time) and extrudes
; at that exact speed continuously, so you can dial in / watch flow around the
; ~600 mm/min ceiling the ladder found. Loops so you can re-run at a new speed
; without restarting the macro.
;
; Runs as ONE continuous move per run (no segmenting) so the screw holds a true
; constant speed. Enter a large run time for "basically continuous".
;
; TO STOP EARLY: cancel the running macro in DWC, or use the emergency stop. A
; run also ends on its own when the time is up.
;
; Requires the extruder to be hot (run Stage 1 first).
; -----------------------------------------------------------------------------

if !exists(global.petgCfgLoaded)
    M98 P"00_Config.g"                    ; for the hot-check target + optional mm^3 readout

var target = 235
if exists(global.petgNozzleTemp)
    set var.target = global.petgNozzleTemp

if heat.heaters[0].current < (var.target - 10)
    M291 P{"Nozzle only " ^ heat.heaters[0].current ^ " C. Run Stage 1 (Heat & Soak) first."} R"Jog Extrude - not hot" S1 T0
    M99

M83                                       ; relative extrusion

var speed = 300                           ; mm/min E, remembered between runs as the default
var secs  = 60                            ; s, remembered between runs as the default
var again = true
while var.again
    M291 P"Extrusion speed (mm/min E)?" R"Jog Extrude - speed" S6 L1 H2000 F{var.speed}
    set var.speed = input
    M291 P"Run for how many seconds? (big number = near-continuous)" R"Jog Extrude - duration" S6 L1 H3600 F{var.secs}
    set var.secs = input

    M203 E{var.speed * 2}                 ; make sure the E speed limit won't clamp us (persists until config reload/reboot)

    echo "Jog: extruding at", var.speed, "mm/min for", var.secs, "s."
    if exists(global.petgMm3PerEmm)
        if global.petgMm3PerEmm > 0
            echo "     ~", (var.speed / 60) * global.petgMm3PerEmm, "mm^3/s"

    M117 {"Jog " ^ var.speed ^ " mm/min (" ^ var.secs ^ "s)"}
    G1 E{var.speed * var.secs / 60} F{var.speed}
    M400

    M117 "Jog run done"
    M291 P{"Ran " ^ var.secs ^ "s at " ^ var.speed ^ " mm/min. Run again?"} R"Jog Extrude" S4 K{"Run again","Stop"} T0
    if input == 1
        set var.again = false
    ; input 0 -> loop; the S6 prompts default to the last values you used

G1 E-2 F120                               ; small relief retraction
M400
M117 "Jog finished"
echo "Jog extrude finished."
