; pulsar_cooldown.g — turn both zone heaters off.
;
; Barrel (H0) and nozzle (H1) each have their own single-heater tool
; (tool 1 and tool 2 — see config.g), so they're addressed via M568 Pn,
; not through tool 0 (which owns the extruder drive, not the heaters).
; A0 forces the heater into "off" state directly — G10 alone only sets
; target values, it doesn't change heater state (see pulsar_preheat.g).

M568 P1 A0
M568 P2 A0

; Drop the Duet→UR ready signal. No-op until M42 is wired up.
M98 P"0:/macros/pulsar_signal_clear.g"
