; pulsar_cooldown.g — turn both zone heaters off.
;
; Barrel (H0) and nozzle (H1) each have their own single-heater tool
; (tool 1 and tool 2 — see config.g), so they're addressed via G10 Pn,
; not through tool 0 (which owns the extruder drive, not the heaters).

G10 P1 S-273.1 R-273.1
G10 P2 S-273.1 R-273.1

; Drop the Duet→UR ready signal. No-op until M42 is wired up.
M98 P"0:/macros/pulsar_signal_clear.g"
