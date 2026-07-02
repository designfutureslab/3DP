; PETG_Max_Flow_Test.g
; =============================================================================
; Self-contained, single-file version of the PETG pellet MAX-FLOW test for the
; DYZE Pulsar Atom. Run it straight from DWC (upload to 0:/gcodes/ and "Start",
; or drop in 0:/macros/ and press the button). It heats, soaks, primes, then
; walks a rising extrusion-speed ladder, pausing at each rung to ask (via a DWC
; dialog) whether the screw kept up. When you report a stall it records the last
; good speed and cools down.
;
; Prefer clicking through the stages one at a time? Use the split macros in the
; ./macros folder instead (00_Config .. 04_Cooldown).
;
; !! DRY THE PELLETS -- PETG is hygroscopic. Wet pellets sputter and read as a
;    false stall. Keep a container ready to catch the purge.
; =============================================================================

; ---------------------------- EDIT YOUR VALUES -------------------------------
var nozzleTemp   = 235      ; C  (PETG pellet ~220-245; long melt zone likes lower)
var soakSeconds  = 480      ; s  heat soak after reaching temp
var primeFeed    = 120      ; mm/min E
var primeLen     = 40       ; mm E per prime slug
var ladderStart  = 60       ; mm/min E  first rung
var ladderStep   = 30       ; mm/min E  increment per rung
var ladderMax    = 900      ; mm/min E  last rung
var stepSeconds  = 20       ; s  extrude time at each rung
var emmPerRev    = 0        ; mm E per screw rev (0 = skip RPM readout)
var mm3PerEmm    = 0        ; mm^3 per mm E (0 = skip volumetric readout)
; -----------------------------------------------------------------------------

M291 P{"Heat to " ^ var.nozzleTemp ^ " C, soak " ^ (var.soakSeconds/60) ^ " min, prime, then ladder " ^ var.ladderStart ^ "->" ^ var.ladderMax ^ " mm/min. Pellets dry? Catch tray ready?"} R"PETG Max-Flow Test" S4 K{"Start","Cancel"} T0
if input != 0
    echo "Test cancelled."
    M99

; --- heat & soak ---------------------------------------------------------------
M568 P0 S{var.nozzleTemp} A2
M117 "Heating to PETG temp..."
M116
echo "At temperature. Soaking", var.soakSeconds, "s."
var remain = var.soakSeconds
while var.remain > 0
    M117 {"Heat soak: " ^ var.remain ^ " s left"}
    G4 S1
    set var.remain = var.remain - 1

; --- prime ---------------------------------------------------------------------
M83                                                  ; relative extrusion
var priming = true
while var.priming
    M117 "Priming..."
    G1 E{var.primeLen} F{var.primeFeed}
    M400
    M291 P"Clean, steady flow?" R"PETG Max-Flow - Prime" S4 K{"Clean - go","Purge again","Stop"} T0
    if input == 0
        set var.priming = false
    elif input == 2
        M568 P0 A0
        echo "Stopped during prime; heater off."
        M99

; --- flow ladder ---------------------------------------------------------------
M203 E{var.ladderMax * 2}                            ; raise E speed limit so the ladder isn't clamped
var feed = var.ladderStart
var stalled = false
var lastGood = 0
while var.feed <= var.ladderMax
    echo "--- Rung:", var.feed, "mm/min E for", var.stepSeconds, "s ---"
    if var.emmPerRev > 0
        echo "    ~", var.feed / var.emmPerRev, "screw RPM"
    if var.mm3PerEmm > 0
        echo "    ~", (var.feed / 60) * var.mm3PerEmm, "mm^3/s"
    M117 {"Ladder: " ^ var.feed ^ " mm/min"}
    G1 E{var.feed * var.stepSeconds / 60} F{var.feed}
    M400
    M291 P{"Extruded at " ^ var.feed ^ " mm/min. Did the screw KEEP UP (steady output, no thinning / pulsing / stall)?"} R"PETG Max-Flow - judge rung" S4 K{"Good - faster","STALLED - stop","Abort"} T0
    if input == 1
        set var.lastGood = var.feed - var.ladderStep
        set var.stalled = true
        break
    elif input == 2
        echo "Aborted at", var.feed, "mm/min."
        M568 P0 A0
        M99
    set var.feed = var.feed + var.ladderStep

; --- report & cool down --------------------------------------------------------
if var.stalled
    echo "STALL at", var.feed, "mm/min. Max reliable =", var.lastGood, "mm/min E."
    M291 P{"RESULT: max reliable extrusion = " ^ var.lastGood ^ " mm/min E (stall began at " ^ var.feed ^ " mm/min). Cooling down."} R"PETG Max-Flow - RESULT" S1 T0
else
    echo "No stall up to", var.ladderMax, "mm/min. Raise ladderMax and re-run."
    M291 P{"No stall up to " ^ var.ladderMax ^ " mm/min. Increase ladderMax and run again."} R"PETG Max-Flow - no stall yet" S1 T0

G1 E-2 F120                                          ; small relief retraction
M400
M568 P0 A0                                           ; heater off
M117 "Test complete - cooling"
echo "PETG max-flow test complete. Heater off."
