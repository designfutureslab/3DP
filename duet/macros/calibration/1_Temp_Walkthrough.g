; Calibration 1 — print-temperature walkthrough (interactive, DWC).
;
; Guides the operator to a good barrel/nozzle pair for a new material:
; enter starting temps → preheat (blocking) → soak → repeated 30 mm test
; extrusions, nudging both zones ±10 °C between tries until the operator
; accepts. Result is echoed and appended to 0:/sys/pulsar-temps.csv.
;
; Uses M291 interactive dialogs (RRF 3.5+): S7 string, S5 integer,
; S4 multiple-choice (result index in `input`, 0-based).
;
; Run with pellets loaded. The test extrusions are 30 mm E @ F300.
;
; Block terminators: dedent-based (this RRF rejects `end`/`endif`).

M291 S7 R"Temp walkthrough" P"Material name (e.g. PETG-black)" T0
var mat = input

M291 S5 R"Temp walkthrough" P"Starting BARREL temp (Top, H0) degC" L120 H280 F215 T0
var barrel = input

M291 S5 R"Temp walkthrough" P"Starting NOZZLE temp (Bottom, H1) degC" L120 H300 F245 T0
var nozzle = input

M291 S3 R"Temp walkthrough" P"Preheating — this blocks until both zones are at temp. OK to start." T0
M568 P1 S{var.barrel} R{var.barrel} A2
M568 P2 S{var.nozzle} R{var.nozzle} A2
M116 P1
M116 P2

M291 S3 R"Temp walkthrough" P"At temp. Let the barrel HEAT-SOAK for 3-5 min so the pellets in the flights melt through, then press OK." T0

; make sure the daemon isn't running, then test-extrude in a loop
set global.pulsar_running = false
M400
T0
M83

var done = false
while !var.done
  G1 E30 F300
  M400
  M291 S4 R"Temp walkthrough" P{"Test at barrel=" ^ var.barrel ^ " nozzle=" ^ var.nozzle ^ ". How does the extrusion look?"} K{"Good - accept","Hotter (+10 both)","Cooler (-10 both)","Abort"} T0
  if input = 0
    set var.done = true
  if input = 1
    set var.barrel = var.barrel + 10
    set var.nozzle = var.nozzle + 10
    M568 P1 S{var.barrel} R{var.barrel} A2
    M568 P2 S{var.nozzle} R{var.nozzle} A2
    M116 P1
    M116 P2
  if input = 2
    set var.barrel = var.barrel - 10
    set var.nozzle = var.nozzle - 10
    M568 P1 S{var.barrel} R{var.barrel} A2
    M568 P2 S{var.nozzle} R{var.nozzle} A2
    M116 P1
    M116 P2
  if input = 3
    abort "Temp walkthrough aborted"

echo "TEMPS ACCEPTED for " ^ var.mat ^ ": barrel=" ^ var.barrel ^ " nozzle=" ^ var.nozzle
echo >>"0:/sys/pulsar-temps.csv" var.mat ^ "," ^ var.barrel ^ "," ^ var.nozzle
M291 S1 R"Temp walkthrough" P{"Saved: " ^ var.mat ^ " barrel=" ^ var.barrel ^ " nozzle=" ^ var.nozzle ^ " -> 0:/sys/pulsar-temps.csv. Heaters left ON."} T5
