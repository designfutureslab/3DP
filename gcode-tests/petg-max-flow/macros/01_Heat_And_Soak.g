; 01_Heat_And_Soak.g
; -----------------------------------------------------------------------------
; STAGE 1 -- bring the extruder to PETG temperature and heat-soak the barrel.
; Safe to press at any time. Does not extrude.
; -----------------------------------------------------------------------------

if !exists(global.petgCfgLoaded)
    M98 P"00_Config.g"

M291 P{"Set nozzle to " ^ global.petgNozzleTemp ^ " C and soak for " ^ (global.petgSoakSeconds/60) ^ " min?"} R"PETG Max-Flow - Stage 1: Heat & Soak" S4 K{"Heat now","Cancel"} T0
if input != 0
    echo "Heat & soak cancelled."
    M99

; --- set temperatures ----------------------------------------------------------
; Primary tool heater (nozzle / lower zone). Waits for temp with M116.
M568 P0 S{global.petgNozzleTemp} A2      ; set tool 0 active temp, heater on
;
; OPTIONAL multi-zone: uncomment and adapt to YOUR heater mapping (M950/M563).
; The Pulsar Atom has 3 zones (top/feed, middle, nozzle). If the extra zones are
; extra heaters on tool 0, set them here; if they are standalone heaters, drive
; them with M104/M141 using the correct heater index. Examples:
; M104 P1 S{global.petgMidZoneTemp}      ; middle zone = heater 1 (adjust index)
; M104 P2 S{global.petgTopZoneTemp}      ; top   zone = heater 2 (adjust index)

M117 "Heating to PETG temp..."
M116                                     ; wait for all heaters to reach target

; --- heat soak with a live countdown ------------------------------------------
echo "At temperature. Soaking", global.petgSoakSeconds, "s so the whole melt zone stabilises."
var remain = global.petgSoakSeconds
while var.remain > 0
    M117 {"Heat soak: " ^ var.remain ^ " s left"}
    G4 S1
    set var.remain = var.remain - 1

M117 "Soak complete - ready to prime"
M291 P"Barrel is soaked and at temperature. Next: press Stage 2 (Prime)." R"PETG Max-Flow - Stage 1 done" S1 T10
