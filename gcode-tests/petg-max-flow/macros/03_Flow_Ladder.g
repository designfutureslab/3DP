; 03_Flow_Ladder.g
; -----------------------------------------------------------------------------
; STAGE 3 -- the actual MAX-FLOW test.
;
; Extrudes at a rising ladder of speeds. At each rung it extrudes for
; petgStepSeconds, then STOPS and asks you (via a DWC dialog) whether the screw
; kept up. When you report a stall / skip / under-extrusion, it records the last
; good speed in global.petgMaxGoodFeed and ends.
;
; "Motor torqued on the pellet" = the screw can no longer push melt fast enough:
; you'll see the output thin out or pulse, hear the motor load up, or (on a
; closed-loop/servo drive) get a following-error. That rung is the ceiling; the
; previous rung is your usable max.
;
; Requires temperature + prime (Stages 1 and 2) first.
; -----------------------------------------------------------------------------

if !exists(global.petgCfgLoaded)
    M98 P"00_Config.g"

if heat.heaters[0].current < (global.petgNozzleTemp - 10)
    M291 P{"Nozzle is only " ^ heat.heaters[0].current ^ " C. Run Stage 1 first."} R"PETG Max-Flow - not hot enough" S1 T0
    M99

M291 P{"Run the flow ladder from " ^ global.petgLadderStart ^ " to " ^ global.petgLadderMax ^ " mm/min in +" ^ global.petgLadderStep ^ " steps, " ^ global.petgStepSeconds ^ " s each? Have something ready to catch the extrudate."} R"PETG Max-Flow - Stage 3: Flow Ladder" S4 K{"Start","Cancel"} T0
if input != 0
    echo "Flow ladder cancelled."
    M99

M83                                                  ; relative extrusion
M203 E{global.petgLadderMax * 2}                     ; raise E speed limit so the ladder isn't clamped (persists until reboot/config reload)
set global.petgMaxGoodFeed = 0

var feed = global.petgLadderStart
var stalled = false
while var.feed <= global.petgLadderMax
    echo "--- Rung:", var.feed, "mm/min E for", global.petgStepSeconds, "s ---"
    if global.petgEmmPerRev > 0
        echo "    ~", var.feed / global.petgEmmPerRev, "screw RPM"
    if global.petgMm3PerEmm > 0
        echo "    ~", (var.feed / 60) * global.petgMm3PerEmm, "mm^3/s"
    M117 {"Ladder: " ^ var.feed ^ " mm/min"}
    G1 E{var.feed * global.petgStepSeconds / 60} F{var.feed}
    M400                                             ; wait for the rung to finish
    M291 P{"Extruded at " ^ var.feed ^ " mm/min. Did the screw KEEP UP (steady output, no thinning / pulsing / motor stall)?"} R"PETG Max-Flow - judge this rung" S4 K{"Good - go faster","STALLED - stop","Abort"} T0
    if input == 1
        set global.petgMaxGoodFeed = var.feed - global.petgLadderStep
        set var.stalled = true
        break
    elif input == 2
        echo "Ladder aborted by operator at", var.feed, "mm/min."
        M99
    ; input = 0 -> good, continue
    set var.feed = var.feed + global.petgLadderStep

; --- report --------------------------------------------------------------------
if var.stalled
    echo "STALL at", var.feed, "mm/min. Last good speed =", global.petgMaxGoodFeed, "mm/min E."
    M291 P{"Max reliable extrusion (last good rung) = " ^ global.petgMaxGoodFeed ^ " mm/min E. Stall began at " ^ var.feed ^ " mm/min. Run Stage 4 to cool down."} R"PETG Max-Flow - RESULT" S1 T0
else
    echo "Reached ladder top", global.petgLadderMax, "mm/min without a reported stall. Raise petgLadderMax in 00_Config.g and re-run to find the ceiling."
    M291 P{"No stall up to the ladder top (" ^ global.petgLadderMax ^ " mm/min). Increase petgLadderMax in Config and run again to find the real ceiling."} R"PETG Max-Flow - no stall yet" S1 T0

M117 "Flow ladder done"
