; pulsar_start.g — begin continuous extrusion via the daemon.
;
; Usage:  M98 P"pulsar_start.g" F<feed_mm_per_min> R<initial_flow_pct>
; e.g.    M98 P"pulsar_start.g" F900 R100
;
; After this returns, global.pulsar_running is true and the daemon is
; topping up the move queue. Modulate flow at runtime via pulsar_flow.g
; (M221). Stop with pulsar_stop.g.

M98 P"pulsar_init.g"

var feed = 900
var flow = 100
if exists(param.F)
  set var.feed = param.F
end
if exists(param.R)
  set var.flow = param.R
end

; Recalculate dwell so the daemon queues a new chunk just before the
; current one drains. Dwell = chunk-duration * 0.95, in whole seconds.
set global.pulsar_feed  = var.feed
set global.pulsar_dwell = floor(global.pulsar_chunk * 60 / var.feed * 0.95)

T0                        ; ensure Pulsar tool is current
M83                       ; relative extrusion
G92 E0                    ; zero the E origin for clean per-chunk moves
M221 S{var.flow}          ; initial flow multiplier

set global.pulsar_running = true
