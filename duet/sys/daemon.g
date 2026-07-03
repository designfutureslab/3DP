; daemon.g — Pulsar continuous-extrusion background task
;
; RRF auto-runs this file, but only re-invokes it every few seconds when
; it returns quickly (observed ~5-6 s on Ric's Duet). Feeding ONE short
; chunk per invocation therefore produced one blip every 5-6 s — a
; stutter, not continuous motion. Fix: loop INTERNALLY here with a
; `while`, so the screw is fed tightly regardless of how often RRF
; re-invokes the file.
;
; HOW IT WORKS
;   While global.pulsar_running is true (and feed > 0), we sit in the
;   while loop feeding one SHORT chunk per iteration, each followed by a
;   dwell of 0.9 × the chunk's run-time. G1 returns as soon as the move
;   is QUEUED, so chunk N+1 is queued while chunk N runs; the 0.9 factor
;   keeps the queue ~1 move deep — continuous motion, no gap, but shallow
;   enough that a pause/rate change bites within ~1 chunk.
;
;   Live control still works from inside the loop:
;   - global.pulsar_feed is re-read every iteration → a rate change over
;     Telnet re-paces on the next chunk.
;   - global.pulsar_running is re-checked every iteration → clearing it
;     (the robot's pause/stop) exits the loop within ~1 chunk.
;   Both are set directly over Telnet as meta-commands, processed on the
;   Telnet channel concurrently with this daemon-channel loop.
;
;   When running is false we fall through to a short idle dwell and
;   return; RRF re-invokes us a few seconds later and we idle again until
;   running goes true.
;
;   pulsar_feed must be > 0 while running (it divides the dwell). Pause
;   is done by clearing pulsar_running, never by feed=0, so the loop
;   only ever sees a positive feed. The `> 0` guard makes that explicit
;   and dodges a divide-by-zero if a bad value slips through.
;
; Block terminators: dedent-based (RRF 3.6 on Ric's Duet rejects both
; bare `end` and `endif`). The `G4 S0.2` at column 0 closes the while
; loop; it runs once after the loop exits, then the file returns.
;
; Tuning globals (set by pulsar_init.g / pulsar_start.g):
;   pulsar_running — bool, true while the daemon should feed chunks
;   pulsar_feed    — F-value (mm/min); the live rate/"flow" knob
;   pulsar_chunk   — mm of E per chunk (short = more responsive pause)

while exists(global.pulsar_running) && global.pulsar_running && global.pulsar_feed > 0
  G1 E{global.pulsar_chunk} F{global.pulsar_feed}
  G4 S{global.pulsar_chunk / global.pulsar_feed * 60 * 0.9}
G4 S0.2
