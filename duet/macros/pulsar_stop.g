; pulsar_stop.g — stop continuous extrusion cleanly.
;
; This is the canonical "return to safe idle" for the extruder. Also used
; as the Stop & Clear debug button (see macros/debug/).
;
; Order matters:
;   1. Clear pulsar_running FIRST so daemon.g stops queuing new chunks.
;   2. M400 drains the chunks already in the look-ahead queue. Without
;      this the screw keeps turning until the buffered moves finish on
;      their own — which, with the no-dwell daemon, is a few cm of extra
;      extrusion after you thought you'd stopped. M400 makes "stopped"
;      mean stopped. (This is the most likely cause of the "never stopped
;      extruding at the end of the print" symptom.)
;   3. M221 S0 / M84 E — zero flow factor and release the extruder motor.
;
; Heaters are left ON — call pulsar_cooldown.g (or the Cooldown button)
; to turn them off. Keeping them hot lets you restart a print quickly.
;
; Block terminators: dedent-based (see daemon.g).

M98 P"0:/sys/pulsar_init.g"

set global.pulsar_running = false   ; daemon stops queuing new chunks
M400                                 ; wait for already-queued chunks to drain
M221 S0                              ; zero any leftover extrusion factor
M84 E                                ; release the extruder motor

; Drop the Duet→UR ready signal. No-op until M42 is wired up.
M98 P"0:/macros/pulsar_signal_clear.g"
