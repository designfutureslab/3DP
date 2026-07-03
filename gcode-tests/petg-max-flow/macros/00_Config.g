; 00_Config.g
; -----------------------------------------------------------------------------
; Shared configuration for the PETG pellet MAX-FLOW test suite.
;
; This macro ONLY defines RepRapFirmware global variables. It does not move or
; heat anything. Every other stage macro calls this first, so edit your numbers
; HERE and they apply everywhere. Re-running this macro after an edit updates the
; live values (the variables persist for the whole DWC session, until reboot).
;
; NOTE ON UNITS -----------------------------------------------------------------
; On a screw pellet extruder there is no filament, so the "E" axis is a pure
; calibration abstraction: E feedrate is in mm/min of *commanded extrudate* as
; defined by your steps/mm (M92 E...). The absolute numbers below are starting
; guesses -- the POINT of the test is the relative ladder and where the screw
; stalls, not the exact mm value. Tune to your machine's calibration.
; -----------------------------------------------------------------------------

; --- declare-once block (placeholders); real values are always set below -------
if !exists(global.petgCfgLoaded)
    global petgNozzleTemp   = 0     ; nozzle / lower zone active temp (C)
    global petgMidZoneTemp  = 0     ; middle zone temp (C)   -- optional, see notes
    global petgTopZoneTemp  = 0     ; top / feed zone temp (C)-- optional, see notes
    global petgSoakSeconds  = 0     ; heat-soak dwell after reaching temp (s)
    global petgPrimeFeed    = 0     ; prime extrusion feedrate (mm/min E)
    global petgPrimeLen     = 0     ; prime extrusion length per press (mm E)
    global petgLadderStart  = 0     ; first speed in the ladder (mm/min E)
    global petgLadderStep   = 0     ; speed increment per rung (mm/min E)
    global petgLadderMax     = 0    ; last speed in the ladder (mm/min E)
    global petgStepSeconds  = 0     ; how long to extrude at each rung (s)
    global petgEmmPerRev    = 0     ; mm of E per screw revolution (0 = unknown/skip RPM readout)
    global petgMm3PerEmm    = 0     ; mm^3 of melt per mm of E (0 = unknown/skip volumetric readout)
    global petgMaxGoodFeed  = 0     ; result: last speed that kept up before stall (written by ladder)
    global petgCfgLoaded    = true

; --- EDIT YOUR VALUES HERE -----------------------------------------------------
; PETG pellet on the Pulsar Atom. Starting point: run all zones flat, then, per
; Dyze's guidance, drop the TOP/feed zone in ~10 C steps if pellets bridge or the
; screw whines/jams at the throat. PETG pellet melts well ~220-245 C; the long
; melt zone means lower is often better. DRY THE PELLETS -- PETG is hygroscopic.
set global.petgNozzleTemp  = 235
set global.petgMidZoneTemp = 235
set global.petgTopZoneTemp = 235

set global.petgSoakSeconds = 480          ; 8 min soak so the whole barrel is at temp

set global.petgPrimeFeed   = 120
set global.petgPrimeLen    = 40

; The ladder: extrude for petgStepSeconds at each speed, stepping up until stall.
set global.petgLadderStart = 60
set global.petgLadderStep  = 30
set global.petgLadderMax   = 900
set global.petgStepSeconds = 20

; Optional readouts. Fill these in from your calibration to see RPM / volumetric
; flow printed at each rung. Leave at 0 to skip.
set global.petgEmmPerRev   = 0            ; e.g. if 1 screw rev == X mm of E
set global.petgMm3PerEmm   = 0            ; e.g. mm^3 pushed per mm of E

echo "PETG max-flow config loaded. Nozzle target", global.petgNozzleTemp, "C. Ladder", global.petgLadderStart, "->", global.petgLadderMax, "step", global.petgLadderStep, "mm/min."
