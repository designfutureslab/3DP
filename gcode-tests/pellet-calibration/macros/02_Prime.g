; 02_Prime.g
; -----------------------------------------------------------------------------
; STAGE 2 -- fill the melt zone and confirm clean, steady flow before testing.
; Extrudes matPrimeLen mm at matPrimeFeed, then asks whether to purge again.
; Requires the extruder to already be at temperature (run Stage 1 first).
; -----------------------------------------------------------------------------

if !exists(global.matCfgLoaded)
    M98 P"00_Config.g"

; Refuse to extrude cold -- protects against pushing solid pellets through.
if heat.heaters[0].current < (global.matNozzleTemp - 10)
    M291 P{"Nozzle is only " ^ heat.heaters[0].current ^ " C. Run Stage 1 (Heat & Soak) first."} R"Not hot enough" S1 T0
    M99

M83                                      ; relative extrusion for the whole test

; Loop: purge a slug, let the operator judge, repeat until flow is clean.
var again = true
while var.again
    M117 "Priming..."
    echo "Priming: extruding", global.matPrimeLen, "mm E at", global.matPrimeFeed, "mm/min."
    G1 E{global.matPrimeLen} F{global.matPrimeFeed}
    M400                                 ; finish the move before asking
    M291 P"Is the flow clean and steady (no sputtering, gaps, or trapped air)?" R"Stage 2: Prime" S4 K{"Clean - done","Purge again","Stop"} T0
    if input == 0
        set var.again = false
    elif input == 2
        echo "Prime stopped by operator."
        M99

M117 "Primed - ready for tests"
M291 P"Priming complete. Next: Stage 3 (max), 06 (min), then 07 (flow cal)." R"Stage 2 done" S1 T10
