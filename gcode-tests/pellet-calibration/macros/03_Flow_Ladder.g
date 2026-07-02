; 03_Flow_Ladder.g
; -----------------------------------------------------------------------------
; STAGE 3 -- find the MAXIMUM extrusion rate.
;
; Extrudes at a rising ladder of speeds. At each rung it extrudes for
; matStepSeconds, then STOPS and asks (via a DWC dialog) whether the screw kept
; up. When you report a stall / skip / under-extrusion it records the last good
; speed in global.matMaxFeed (used by the flow calibration) and ends.
;
; "Motor torqued on the pellet" = the screw can no longer push melt fast enough:
; the output thins or pulses, the motor loads up audibly, or a closed-loop drive
; throws a following-error. That rung is the ceiling; the rung below is your max.
;
; Requires temperature + prime (Stages 1 and 2) first.
; -----------------------------------------------------------------------------

if !exists(global.matCfgLoaded)
    M98 P"00_Config.g"

if heat.heaters[0].current < (global.matNozzleTemp - 10)
    M291 P{"Nozzle is only " ^ heat.heaters[0].current ^ " C. Run Stage 1 first."} R"Not hot enough" S1 T0
    M99

echo "Ladder:", global.matLadderStart, "->", global.matLadderMax, "mm/min, +", global.matLadderStep, "per rung,", global.matStepSeconds, "s each."
M291 P"Run the flow ladder? Have a tray ready to catch the extrudate." R"Stage 3: Max Flow" S4 K{"Start","Cancel"} T0
if input != 0
    echo "Flow ladder cancelled."
    M99

M83                                                  ; relative extrusion
M203 E{global.matLadderMax * 2}                      ; raise E speed limit so the ladder isn't clamped (persists until reboot/config reload)

var feed = global.matLadderStart
var stalled = false
while var.feed <= global.matLadderMax
    echo "--- Rung:", var.feed, "mm/min E for", global.matStepSeconds, "s ---"
    if global.matEmmPerRev > 0
        echo "    ~", var.feed / global.matEmmPerRev, "screw RPM"
    if global.matMm3PerEmm > 0
        echo "    ~", (var.feed / 60) * global.matMm3PerEmm, "mm^3/s"
    M117 {"Ladder: " ^ var.feed ^ " mm/min"}
    G1 E{var.feed * global.matStepSeconds / 60} F{var.feed}
    M400                                             ; wait for the rung to finish
    M291 P{"Extruded at " ^ var.feed ^ " mm/min. Did the screw KEEP UP (steady, no thinning/pulsing)?"} R"Judge this rung" S4 K{"Good - faster","STALLED - stop","Abort"} T0
    if input == 1
        set global.matMaxFeed = var.feed - global.matLadderStep
        set var.stalled = true
        break
    elif input == 2
        echo "Ladder aborted by operator at", var.feed, "mm/min."
        M99
    ; input = 0 -> good, continue
    set var.feed = var.feed + global.matLadderStep

; --- report --------------------------------------------------------------------
if var.stalled
    echo "STALL at", var.feed, "mm/min. Saved matMaxFeed =", global.matMaxFeed, "mm/min E."
    M291 P{"Max reliable = " ^ global.matMaxFeed ^ " mm/min E (stall at " ^ var.feed ^ " mm/min). Saved. Next: 06 (min) then 07 (flow cal)."} R"RESULT - max" S1 T0
else
    set global.matMaxFeed = global.matLadderMax
    echo "No stall up to", global.matLadderMax, "mm/min. Raise matLadderMax in 00_Config.g and re-run to find the real ceiling."
    M291 P{"No stall up to " ^ global.matLadderMax ^ " mm/min. Increase matLadderMax and run again to find the ceiling."} R"No stall yet" S1 T0

M117 "Flow ladder done"
