; pulsar_start.g — begin continuous extrusion via the daemon (v3).
;
; Usage:  M98 P"pulsar_start.g" F<feed_mm_per_min>
; e.g.    M98 P"pulsar_start.g" F600
;
; After this returns, global.pulsar_running is true and the daemon feeds
; time-sized chunks (~pulsar_latency seconds each) — the screw runs
; continuously. Live rate = set global.pulsar_feed. Pause = clear
; global.pulsar_running (or pause the UR, if the hardware gate is wired
; and enabled). Stop with pulsar_stop.g.
;
; CLEAN-SLATE START — stops and drains FIRST so a print can never inherit
; stale state from a previous run or bench test (leftover running=true,
; a half-drained queue, a hand-set M221). Starting IS the reset.
;
; Block terminators: dedent-based (see daemon.g).

M98 P"0:/sys/pulsar_init.g"

var feed = 600
if exists(param.F)
  set var.feed = param.F

; --- clean slate: stop daemon and drain any leftover queued extrusion ---
set global.pulsar_running = false
M400

; --- known extrusion state ---
T0                        ; ensure Pulsar tool is current
M83                       ; relative extrusion
G92 E0                    ; zero the E origin
M221 S100                 ; clear any leftover extrusion factor

; --- go ---
set global.pulsar_feed = var.feed
set global.pulsar_running = true
