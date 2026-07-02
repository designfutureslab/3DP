; 00_Config.g
; -----------------------------------------------------------------------------
; Shared configuration for the PELLET calibration suite (generic, any material).
;
; This macro ONLY defines RepRapFirmware global variables -- it does not move or
; heat anything. Every other stage calls it first, so edit your numbers HERE.
; Re-running it after an edit updates the live values (globals persist for the
; whole DWC session, until reboot).
;
; HOW TO USE:
;   1. Set matName below to your material (PLA/PETG/ABS/ASA/PC/TPU/PA/PP or CUSTOM).
;   2. The preset block fills in sensible STARTING temps + a flow window.
;   3. Override anything under "PER-RUN OVERRIDES" if you want.
;   4. As you run the tests, matMinFeed / matMaxFeed get refined for your setup.
;
; See MATERIAL_TEMPERATURES.md for where these numbers come from and caveats.
;
; UNITS: on a screw pellet extruder there is no filament, so the "E" axis is a
; pure calibration abstraction -- E feedrate is mm/min of *commanded extrudate*
; per your steps/mm (M92 E...). Treat the mm numbers as relative; the tests care
; about the ratios and where the screw stalls, not the absolute mm value.
; -----------------------------------------------------------------------------

; --- declare-once block (placeholders); real values are always set below -------
if !exists(global.matCfgLoaded)
    global matName        = "PETG"   ; material selector (see preset block)
    global matNozzleTemp  = 0        ; nozzle / lower zone active temp (C)
    global matMidZoneTemp = 0        ; middle zone temp (C)  -- optional, see 01
    global matTopZoneTemp = 0        ; top / feed zone temp (C) -- optional, see 01
    global matBedTemp     = 0        ; bed temp (C), 0 = leave bed alone
    global matDensity     = 0        ; g/cm^3, for mass<->volume in flow calibration
    global matSoakSeconds = 0        ; heat-soak dwell after reaching temp (s)
    global matPrimeFeed   = 0        ; prime extrusion feedrate (mm/min E)
    global matPrimeLen    = 0        ; prime extrusion length per press (mm E)
    global matMinFeed     = 0        ; established MIN reliable feed (mm/min E) - set by 06
    global matMaxFeed     = 0        ; established MAX reliable feed (mm/min E) - set by 03
    global matLadderStart = 0        ; max-flow ladder: first speed (mm/min E)
    global matLadderStep  = 0        ; max-flow ladder: increment per rung (mm/min E)
    global matLadderMax   = 0        ; max-flow ladder: last speed (mm/min E)
    global matStepSeconds = 0        ; extrude time per rung/sample (s)
    global matEmmPerRev   = 0        ; mm of E per screw revolution (0 = skip RPM readout)
    global matMm3PerEmm   = 0        ; mm^3 of melt per mm of E (0 = skip volumetric readout)
    global matGramsPerEmm = 0        ; RESULT: measured g per mm of E (written by 07)
    global matMaxFlow     = 0        ; RESULT: measured g/s at max feed (written by 07)
    global matCfgLoaded   = true

; =============================================================================
; 1) PICK YOUR MATERIAL
; =============================================================================
set global.matName = "PETG"          ; <-- PLA / PETG / ABS / ASA / PC / TPU / PA / PP / CUSTOM

; =============================================================================
; 2) PRESETS  (starting points -- see MATERIAL_TEMPERATURES.md. Pellet melt zones
;    usually run a touch LOWER than filament figures because residence time is long.)
;    Temps are: nozzle/lower, middle, top/feed zone. Feed window is mm/min E and
;    is machine-specific -- just somewhere to start the ladder from.
; =============================================================================
if global.matName == "PLA"
    set global.matNozzleTemp = 200
    set global.matMidZoneTemp = 195
    set global.matTopZoneTemp = 185
    set global.matBedTemp = 55
    set global.matDensity = 1.24
elif global.matName == "PETG"
    set global.matNozzleTemp = 235
    set global.matMidZoneTemp = 235
    set global.matTopZoneTemp = 230
    set global.matBedTemp = 80
    set global.matDensity = 1.27
elif global.matName == "ABS"
    set global.matNozzleTemp = 245
    set global.matMidZoneTemp = 240
    set global.matTopZoneTemp = 230
    set global.matBedTemp = 100
    set global.matDensity = 1.04
elif global.matName == "ASA"
    set global.matNozzleTemp = 250
    set global.matMidZoneTemp = 245
    set global.matTopZoneTemp = 235
    set global.matBedTemp = 100
    set global.matDensity = 1.07
elif global.matName == "PC"
    set global.matNozzleTemp = 275
    set global.matMidZoneTemp = 270
    set global.matTopZoneTemp = 255
    set global.matBedTemp = 110
    set global.matDensity = 1.20
elif global.matName == "TPU"
    set global.matNozzleTemp = 225
    set global.matMidZoneTemp = 220
    set global.matTopZoneTemp = 210
    set global.matBedTemp = 50
    set global.matDensity = 1.21
elif global.matName == "PA"
    set global.matNozzleTemp = 255
    set global.matMidZoneTemp = 250
    set global.matTopZoneTemp = 240
    set global.matBedTemp = 85
    set global.matDensity = 1.14
elif global.matName == "PP"
    set global.matNozzleTemp = 230
    set global.matMidZoneTemp = 225
    set global.matTopZoneTemp = 215
    set global.matBedTemp = 90
    set global.matDensity = 0.91
else
    ; CUSTOM -- set your own here
    set global.matNozzleTemp = 235
    set global.matMidZoneTemp = 235
    set global.matTopZoneTemp = 230
    set global.matBedTemp = 0
    set global.matDensity = 1.20

; =============================================================================
; 3) PER-RUN OVERRIDES (same for every material unless you change them)
; =============================================================================
set global.matSoakSeconds = 480      ; 8 min soak so the whole barrel is at temp

set global.matPrimeFeed   = 120
set global.matPrimeLen    = 40

; Max-flow ladder (used by 03). Steps up until the screw stalls.
set global.matLadderStart = 60
set global.matLadderStep  = 30
set global.matLadderMax   = 900
set global.matStepSeconds = 20

; Established working window. Leave as-is to let the tests fill them in, or set
; them by hand if you already know them. (PETG example from earlier runs shown.)
set global.matMinFeed     = 120      ; refine with 06_Min_Rate_Finder
set global.matMaxFeed     = 600      ; refine with 03_Flow_Ladder

; Optional calibration constants for live readouts (0 = skip):
set global.matEmmPerRev   = 0        ; mm E per screw rev -> prints screw RPM
set global.matMm3PerEmm   = 0        ; mm^3 per mm E -> prints mm^3/s

echo "Pellet config:", global.matName, "| nozzle", global.matNozzleTemp, "C | window", global.matMinFeed, "-", global.matMaxFeed, "mm/min | density", global.matDensity, "g/cm3"
