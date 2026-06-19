; daemon.g — Pulsar continuous-extrusion background task
;
; RRF auto-runs this file in a loop. Each iteration completes, then RRF
; restarts it. While global.pulsar_running is true, we queue one short
; extrusion chunk and dwell for slightly less than its execution time, so
; the next chunk arrives just before the current one drains — the screw
; never stalls.
;
; When idle, we just sleep so the loop isn't a busy-poll.
;
; Tuning is held in globals (set by pulsar_init.g / pulsar_start.g):
;   pulsar_running  — bool, true while the daemon should top up the queue
;   pulsar_feed     — F-value (mm/min) for each chunk
;   pulsar_chunk    — mm of E per chunk
;   pulsar_dwell    — seconds to sleep between chunks (slightly less than
;                     chunk / feed * 60 so chunks overlap rather than gap)

if exists(global.pulsar_running) && global.pulsar_running
  G1 E{global.pulsar_chunk} F{global.pulsar_feed}
  G4 S{global.pulsar_dwell}
else
  G4 S1
end
