; pulsar_stop.g — stop continuous extrusion.
;
; Clears the daemon's running flag, zeroes flow, and disables the
; extruder motor. Heaters stay on — call pulsar_cooldown.g to cool.

M98 P"pulsar_init.g"

set global.pulsar_running = false
M221 S0
M84 E

; Drop the Duet→UR ready signal. No-op until M42 is wired up.
M98 P"pulsar_signal_clear.g"
