; 06_Min_Rate_Finder.g
; -----------------------------------------------------------------------------
; Find the MINIMUM reliable extrusion rate.
;
; Below some speed a screw pellet extruder stops flowing steadily -- output goes
; intermittent / pulses / dribbles because the melt pressure can't be maintained.
; This macro starts from a known-good speed and steps DOWN until you report that
; flow has become inconsistent, then records the last good speed as
; global.matMinFeed (the low end of the dynamic-flow sweep in Stage 7).
;
; Requires temperature + prime first. Run Stage 3 first if you can, so it starts
; from your established max.
; -----------------------------------------------------------------------------

if !exists(global.matCfgLoaded)
    M98 P"00_Config.g"

if heat.heaters[0].current < (global.matNozzleTemp - 10)
    M291 P{"Nozzle is only " ^ heat.heaters[0].current ^ " C. Run Stage 1 first."} R"Not hot enough" S1 T0
    M99

; Start from the established max if we have one, else half the ladder top.
var start = global.matLadderMax / 2
if global.matMaxFeed > 0
    set var.start = global.matMaxFeed
var floor = global.matLadderStep            ; can't sensibly go below one step

echo "Min-rate finder: stepping DOWN from", var.start, "by", global.matLadderStep, "mm/min,", global.matStepSeconds, "s each."
M291 P{"Step DOWN from " ^ var.start ^ " mm/min until flow gets inconsistent? Catch tray ready?"} R"Min-Rate Finder" S4 K{"Start","Cancel"} T0
if input != 0
    M99

M83
M203 E{var.start * 2}

var feed = var.start
var lastGood = var.start
var found = false
while var.feed >= var.floor
    echo "--- Rung:", var.feed, "mm/min E for", global.matStepSeconds, "s ---"
    M117 {"Min finder: " ^ var.feed ^ " mm/min"}
    G1 E{var.feed * global.matStepSeconds / 60} F{var.feed}
    M400
    M291 P{"At " ^ var.feed ^ " mm/min: is flow still STEADY (no pulsing / gaps / dribble)?"} R"Judge this rung" S4 K{"Yes - go slower","No - inconsistent","Abort"} T0
    if input == 0
        set var.lastGood = var.feed
        set var.feed = var.feed - global.matLadderStep
    elif input == 1
        set global.matMinFeed = var.lastGood
        set var.found = true
        break
    else
        echo "Min finder aborted at", var.feed, "mm/min."
        M99

if !var.found
    set global.matMinFeed = var.lastGood
    echo "Reached the floor still flowing. Min set to", global.matMinFeed, "mm/min (lower matLadderStep to probe finer)."

echo "Saved matMinFeed =", global.matMinFeed, "mm/min E."
M291 P{"Min reliable feed = " ^ global.matMinFeed ^ " mm/min E. Saved. Window is now " ^ global.matMinFeed ^ " - " ^ global.matMaxFeed ^ " mm/min."} R"RESULT - min" S1 T0
M117 "Min-rate finder done"
