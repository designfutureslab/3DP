; Calibration 3 — 10-step gravimetric flow calibration.
;
; Measures ACTUAL deposition (grams on a scale) across 10 extrusion rates
; from Fmin to Fmax, so Grasshopper can map commanded feed → real
; volumetric flow instead of trusting steps/mm. Run AFTER the temp
; walkthrough and rate-limits macros (zones at temp + soaked; use the
; min/max you found).
;
; Per step: prompt → extrude for T seconds at the step's feed → operator
; weighs the extrudate and types the grams in → a CSV row is appended
; immediately (no arrays, nothing lost if you abort mid-run).
;
; Output: 0:/sys/pulsar-flowcal.csv   (OVERWRITTEN each run)
;   material,feed_mm_min,seconds,grams,g_per_min,mm3_per_s
;
; g_per_min  = grams * 60 / seconds
; mm3_per_s  = grams / seconds / density * 1000   (density in g/cm3)
;
; IMPORT INTO GRASSHOPPER — the Duet's web server exposes any SD file at:
;   http://172.22.22.100/rr_download?name=/sys/pulsar-flowcal.csv
; Fetch that URL from GH (Swiftlet plugin, a one-line C# WebClient, or
; just download via DWC → System and read the file) and you have the
; feed→flow curve to drive [F] values per bead-width/layer-height target.
;
; You need a scale with 0.01 g resolution ideally (0.1 g workable at the
; longer test times). 30 s per step at PETG rates gives ~2-15 g samples.
;
; Block terminators: dedent-based.

M291 S7 R"Flow cal" P"Material name" T0
var mat = input

M291 S6 R"Flow cal" P"Material density g/cm3 (PETG 1.27, PLA 1.24)" L0.5 H3 F1.27 T0
var dens = input

M291 S5 R"Flow cal" P"Min feed Fmin (mm/min) - from rate-limits" L10 H3000 F150 T0
var fmin = input

M291 S5 R"Flow cal" P"Max feed Fmax (mm/min) - from rate-limits" L10 H3000 F1200 T0
var fmax = input

M291 S5 R"Flow cal" P"Seconds per step" L5 H120 F30 T0
var secs = input

set global.pulsar_running = false
M400
T0
M83

echo >"0:/sys/pulsar-flowcal.csv" "material,feed_mm_min,seconds,grams,g_per_min,mm3_per_s"

var i = 0
while var.i < 10
  var f = var.fmin + var.i * (var.fmax - var.fmin) / 9
  M291 S3 R"Flow cal" P{"Step " ^ (var.i + 1) ^ "/10 - F" ^ var.f ^ " for " ^ var.secs ^ " s. Zero the scale, hold the catch cup under the nozzle, then press OK."} T0
  G1 E{var.f * var.secs / 60} F{var.f}
  M400
  M291 S6 R"Flow cal" P{"Step " ^ (var.i + 1) ^ "/10 done. Weigh it - enter GRAMS"} L0 H1000 F0 T0
  var g = input
  echo >>"0:/sys/pulsar-flowcal.csv" var.mat ^ "," ^ var.f ^ "," ^ var.secs ^ "," ^ var.g ^ "," ^ (var.g * 60 / var.secs) ^ "," ^ (var.g / var.secs / var.dens * 1000)
  set var.i = var.i + 1

echo "FLOW CAL complete: 0:/sys/pulsar-flowcal.csv"
M291 S1 R"Flow cal" P"Done. Download: http://<duet-ip>/rr_download?name=/sys/pulsar-flowcal.csv (or DWC - System). Heaters left ON." T10
