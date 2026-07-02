; 04_Cooldown.g
; -----------------------------------------------------------------------------
; STAGE 4 -- turn off the heaters. Safe to press at any time.
; Optionally back the screw off slightly to relieve pressure before it freezes.
; -----------------------------------------------------------------------------

if !exists(global.matCfgLoaded)
    M98 P"00_Config.g"

M291 P"Cool down now? This turns off the extruder heater(s)." R"Stage 4: Cooldown" S4 K{"Cool down","Cancel"} T0
if input != 0
    M99

; Small relief retraction while still molten (only if we're hot).
if heat.heaters[0].current > (global.matNozzleTemp - 30)
    M83
    G1 E-2 F120
    M400

M568 P0 A0                               ; tool 0 heater off
if global.matBedTemp > 0
    M140 S0                              ; bed target to 0 (off) -- only if you used the bed
; If you enabled extra zone heaters in Stage 1, turn them off too, e.g.:
; M104 P1 S0
; M104 P2 S0

M117 "Cooling down"
echo "Heaters off. Pellet calibration session complete."
