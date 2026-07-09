; daemon.g — Pulsar continuous-extrusion background task
;
; RRF only re-invokes this file every few seconds when it returns, so we
; loop INTERNALLY with a `while` to keep the screw fed tightly.
;
; NO DWELL BETWEEN CHUNKS. An earlier version put a `G4` dwell after each
; chunk to "pace" the loop — but G4 is a QUEUED motion command, not a
; wall-clock sleep, so it executed as a real stop after every chunk:
; move 0.43 s / stop 0.39 s / move / stop … a visible ~1-2 Hz pulse in
; the bead. Removing it lets consecutive G1 E moves blend in the planner
; (same feed, same direction, within M566 E jerk) into ONE continuous
; rotation — the way a normal print feeds thousands of extrusion moves
; without stopping between them.
;
; Pacing without a dwell: G1 returns as soon as the move is QUEUED, and
; blocks only when RRF's look-ahead queue is full — so the loop
; self-paces to the drain rate once the queue fills. No busy-spin, no CPU
; peg, and the Telnet channel stays free so live `set global.…` commands
; are still processed promptly.
;
; TRADE-OFF — because there's no dwell, the queue fills a few chunks deep,
; so a pause / rate change / stop takes effect after the already-queued
; chunks drain (queue depth × pulsar_chunk of extrusion). Keep pulsar_chunk
; small to bound that: at chunk 2 mm the committed-ahead extrusion is only
; a few cm. For vase mode (no mid-print pause) this is irrelevant; the
; screw just runs smoothly Start→Stop. If you need tighter live control,
; a queue-depth guard (feed only while move.queue depth < N) is the proper
; fix — pending confirmation of the object-model field name on this RRF
; build (run  M409 K"move.queue"  to inspect).
;
; Live control, re-read every iteration:
;   pulsar_feed    — F-value (mm/min); the rate / "flow" knob
;   pulsar_running — bool; clear it to pause (loop exits, screw coasts to
;                    a stop once the queued chunks drain)
;   pulsar_feed must be > 0 while running; the > 0 guard is belt-and-braces.
;
; Block terminators: dedent-based (RRF 3.6 rejects both bare `end` and
; `endif`). The `G4 S0.2` at column 0 closes the while loop and runs once
; after it exits (idle tick), then the file returns.

while exists(global.pulsar_running) && global.pulsar_running && global.pulsar_feed > 0
  G1 E{global.pulsar_chunk} F{global.pulsar_feed}
G4 S0.2
