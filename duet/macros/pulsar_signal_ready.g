; pulsar_signal_ready.g — assert the Duet→UR "ready" signal.
;
; Called automatically from pulsar_preheat.g once both heater zones are at
; target (after M116 returns). The UR is blocked in wait_for_pulsar_enabled
; waiting for this line to go high.
;
; Until the DIO is wired between the Duet and a UR digital input,
; uncomment the M42 line below with the correct output pin. Pin name
; matches an M950 P<n> C"<pin>" definition; common Duet 3 Mini choices
; are "out6", "out7", or one of the GPIO pins on io0..io8.

; M42 P<output_pin> S1
