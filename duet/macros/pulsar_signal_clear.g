; pulsar_signal_clear.g — drop the Duet→UR "ready" signal.
;
; Called automatically from pulsar_stop.g and pulsar_cooldown.g so the
; UR's wait_for_pulsar_enabled returns false from then on. Future use:
; can also be called from an emergency stop or pause path to halt UR
; motion when something's wrong on the Duet side.
;
; Same M42 line as pulsar_signal_ready.g, with S0 instead of S1.

; M42 P<output_pin> S0
