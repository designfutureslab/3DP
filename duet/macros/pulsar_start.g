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
; Rate is now controlled by pulsar_feed (screw speed), not M221. On a
; single-screw pellet extruder screw speed IS the deposition rate, so a
; separate extrusion-factor knob just added queue lag. M221 is reset to
; 100 here so any leftover factor from an earlier run can't scale the
; daemon's chunks.
;
; Block terminators: dedent-based (see daemon.g).

M98 P"0:/sys/pulsar_init.g"

var feed = 600
if exists(param.F)
  set var.feed = param.F

set global.pulsar_feed = var.feed

T0                        ; ensure Pulsar tool is current
M83                       ; relative extrusion
G92 E0                    ; zero the E origin for clean per-chunk moves
M221 S100                 ; clear any leftover extrusion factor

set global.pulsar_running = true
