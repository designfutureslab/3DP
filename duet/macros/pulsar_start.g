; pulsar_start.g — begin continuous extrusion via the daemon.
;
; Usage:  M98 P"pulsar_start.g" F<feed_mm_per_min>
; e.g.    M98 P"pulsar_start.g" F600
;
; After this returns, global.pulsar_running is true and the daemon is
; feeding short chunks — the screw runs continuously. To change the rate
; live, just set global.pulsar_feed (the robot does this directly over
; Telnet, no macro needed). To pause, clear global.pulsar_running. Stop
; with pulsar_stop.g.
;
; CLEAN-SLATE START — we deliberately stop and drain FIRST, so a print
; can never inherit stale state from a previous run or from bench
; testing (e.g. a leftover pulsar_running=true, a half-drained queue, or
; an M221 factor someone set by hand). The sequence is:
;   1. pulsar_running = false + M400  → daemon idle, queue empty
;   2. reset E origin + M221 100      → known extrusion state
;   3. set feed, then pulsar_running = true → screw starts
; This is why the print program doesn't need to "reset vars" itself —
; starting IS the reset.
;
; Rate is controlled by pulsar_feed (screw speed), not M221. On a
; single-screw pellet extruder screw speed IS the deposition rate, so a
; separate extrusion-factor knob just added queue lag.
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
G92 E0                    ; zero the E origin for clean per-chunk moves
M221 S100                 ; clear any leftover extrusion factor

; --- go ---
set global.pulsar_feed = var.feed
set global.pulsar_running = true
