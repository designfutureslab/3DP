; pulsar_cooldown.g — set both zone targets to 0 and turn the tool off.

M568 P0 S0:0 R0:0 A0

; Drop the Duet→UR ready signal. No-op until M42 is wired up.
M98 P"pulsar_signal_clear.g"
