; Calibration 2 — find MIN and MAX extrusion rate at the current temps.
;
; Run AFTER the temp walkthrough (zones at temp, soaked, pellets loaded).
;
; MAX: steps the feed UP from a start value; each step extrudes for a few
; seconds and the operator judges "clean" or "skipping/stalling". Max is
; the last clean step.
; MIN: steps DOWN; min is the last step that still gives a usable,
; continuous bead (below it the flow dribbles/stalls).
;
; Results echoed + appended to 0:/sys/pulsar-limits.csv as
;   material, min_feed, max_feed, barrel, nozzle
;
; Block terminators: dedent-based.

M291 S7 R"Rate limits" P"Material name (match the temp walkthrough)" T0
var mat = input

M291 S5 R"Rate limits" P"MAX search - start feed (mm/min)" L50 H3000 F300 T0
var f = input

M291 S5 R"Rate limits" P"Step size (mm/min)" L10 H500 F100 T0
var step = input

M291 S5 R"Rate limits" P"Seconds per test" L2 H30 F5 T0
var secs = input

set global.pulsar_running = false
M400
T0
M83

; ---- MAX ----
var fmax = 0
var searching = true
while var.searching
  M291 S3 R"Rate limits" P{"Will extrude " ^ var.secs ^ " s at F" ^ var.f ^ ". OK to run."} T0
  G1 E{var.f * var.secs / 60} F{var.f}
  M400
  M291 S4 R"Rate limits" P{"F" ^ var.f ^ " - how was it?"} K{"Clean - go faster","Skipping/stalling - stop here","Abort"} T0
  if input = 0
    set var.fmax = var.f
    set var.f = var.f + var.step
  if input = 1
    set var.searching = false
  if input = 2
    abort "Rate limit search aborted"

; ---- MIN ----
M291 S5 R"Rate limits" P"MIN search - start feed (mm/min)" L10 H1000 F200 T0
set var.f = input

M291 S5 R"Rate limits" P"Step DOWN size (mm/min)" L5 H200 F25 T0
set var.step = input

var fmin = var.f
set var.searching = true
while var.searching && var.f > 0
  G1 E{var.f * var.secs / 60} F{var.f}
  M400
  M291 S4 R"Rate limits" P{"F" ^ var.f ^ " - still a usable continuous bead?"} K{"Yes - go slower","No - stop here","Abort"} T0
  if input = 0
    set var.fmin = var.f
    set var.f = var.f - var.step
  if input = 1
    set var.searching = false
  if input = 2
    abort "Rate limit search aborted"

echo "RATE LIMITS for " ^ var.mat ^ ": min=" ^ var.fmin ^ " max=" ^ var.fmax ^ " (mm/min)"
echo >>"0:/sys/pulsar-limits.csv" var.mat ^ "," ^ var.fmin ^ "," ^ var.fmax ^ "," ^ heat.heaters[0].active ^ "," ^ heat.heaters[1].active
M291 S1 R"Rate limits" P{"Saved: min=F" ^ var.fmin ^ " max=F" ^ var.fmax ^ " -> 0:/sys/pulsar-limits.csv"} T5
