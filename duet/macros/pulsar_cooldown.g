; pulsar_cooldown.g — turn both zone heaters off.
;
; H0/H1 aren't tool members (see config.g) so they're addressed directly
; by heater number, not through the tool — M568 would be a no-op now.

M104 H0 S-273.1
M104 H1 S-273.1

; Drop the Duet→UR ready signal. No-op until M42 is wired up.
M98 P"0:/macros/pulsar_signal_clear.g"
