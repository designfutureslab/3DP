; 07_Dynamic_Flow_Calibration.g
; -----------------------------------------------------------------------------
; DYNAMIC FLOW CALIBRATION -- map commanded extrusion speed to ACTUAL mass flow.
;
; Once you have a min (Stage 6) and max (Stage 3), this sweeps N speeds evenly
; across that window. For each one it extrudes for a set time, you weigh the
; purge on a scale, and type the mass in grams. From that it computes, per point:
;   * actual mass flow      (g/s)
;   * actual volumetric flow (mm^3/s, if material density is set)
;   * grams per mm of commanded E  (the flow "gain")
;
; Screw extruders slip more at high speed, so this relationship is often NON-
; linear -- that's exactly what we're measuring. Results are echoed as CSV-style
; rows (tagged FLOWCAL_ROW) in the DWC console; copy them into Grasshopper to
; drive the Pulsar Flow %. See README ("Using the flow data in Grasshopper").
;
; You need: a scale (0.01 g ideal), a clean container per sample, and the
; extruder hot + primed.
; -----------------------------------------------------------------------------

if !exists(global.matCfgLoaded)
    M98 P"00_Config.g"

if heat.heaters[0].current < (global.matNozzleTemp - 10)
    M291 P{"Nozzle is only " ^ heat.heaters[0].current ^ " C. Run Stage 1 first."} R"Not hot enough" S1 T0
    M99

if global.matMinFeed <= 0 || global.matMaxFeed <= 0 || global.matMaxFeed <= global.matMinFeed
    M291 P"Set a valid min (Stage 6) and max (Stage 3) first: need 0 < min < max." R"Flow cal - window not set" S1 T0
    M99

; --- ask sweep parameters ------------------------------------------------------
M291 P"How many speed points across the min-max window?" R"Flow cal - points" S5 L2 H20 F5
var points = input
M291 P"Extrude time per sample (s)? Longer = more mass = better weigh accuracy." R"Flow cal - time" S6 L5 H600 F{global.matStepSeconds}
var secs = input

var step = (global.matMaxFeed - global.matMinFeed) / (var.points - 1)
M203 E{global.matMaxFeed * 2}
M83

echo "FLOWCAL_HDR, material, speed_mmpm, time_s, cmdE_mm, mass_g, g_per_s, mm3_per_s, g_per_mmE"

; --- accumulators (no arrays needed) ------------------------------------------
var sumGpermm = 0
var minGpermm = 999999
var maxGpermm = 0
var lastGperS = 0
var done = 0

; loop-body vars declared once here (RRF forbids re-declaring 'var' inside a loop)
var speed = 0
var mass = 0
var cmdE = 0
var gPerS = 0
var gPerMm = 0
var mm3PerS = 0

var i = 0
while var.i < var.points
    set var.speed = global.matMinFeed + var.step * var.i
    M291 P{"Sample " ^ (var.i + 1) ^ "/" ^ var.points ^ " at " ^ var.speed ^ " mm/min for " ^ var.secs ^ " s. Place a clean, tared container. Ready?"} R"Flow cal - sample" S4 K{"Extrude","Abort"} T0
    if input != 0
        echo "Flow calibration aborted after", var.done, "samples."
        M99

    M117 {"Flow cal " ^ (var.i + 1) ^ "/" ^ var.points ^ ": " ^ var.speed ^ " mm/min"}
    G1 E{var.speed * var.secs / 60} F{var.speed}
    M400

    M291 P{"Weigh sample " ^ (var.i + 1) ^ ". Enter its mass in grams:"} R"Flow cal - mass (g)" S6 L0 H10000 F0
    set var.mass = input

    set var.cmdE = var.speed * var.secs / 60
    set var.gPerS = var.mass / var.secs
    set var.gPerMm = var.mass / var.cmdE
    set var.mm3PerS = 0
    if global.matDensity > 0
        set var.mm3PerS = (var.mass / global.matDensity) * 1000 / var.secs

    echo "FLOWCAL_ROW,", global.matName, ",", var.speed, ",", var.secs, ",", var.cmdE, ",", var.mass, ",", var.gPerS, ",", var.mm3PerS, ",", var.gPerMm

    set var.sumGpermm = var.sumGpermm + var.gPerMm
    if var.gPerMm < var.minGpermm
        set var.minGpermm = var.gPerMm
    if var.gPerMm > var.maxGpermm
        set var.maxGpermm = var.gPerMm
    set var.lastGperS = var.gPerS
    set var.done = var.done + 1
    set var.i = var.i + 1

; --- summary -------------------------------------------------------------------
var meanGpermm = var.sumGpermm / var.done
set global.matGramsPerEmm = var.meanGpermm
set global.matMaxFlow = var.lastGperS

var spread = 0
if var.meanGpermm > 0
    set var.spread = (var.maxGpermm - var.minGpermm) / var.meanGpermm * 100

echo "FLOWCAL_SUMMARY, mean g/mm_E =", var.meanGpermm, ", spread across points =", var.spread, "%, g/s at max feed =", var.lastGperS
echo "If spread is small (<~10%) flow is ~linear: one Pulsar Flow % works. If large, use the full speed->g/s map (the FLOWCAL_ROW lines) in Grasshopper."
M291 P{"Done. Mean flow gain " ^ var.meanGpermm ^ " g/mm_E, spread " ^ var.spread ^ " %. Copy the FLOWCAL_ROW lines from the console into Grasshopper."} R"Flow cal complete" S1 T0
M117 "Flow calibration done"
