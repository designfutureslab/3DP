; pulsar_unretract.g — unretract the extruder by a fixed amount.
;
; Usage:  M98 P"pulsar_unretract.g" S<mm> F<mm_per_min>
; e.g.    M98 P"pulsar_unretract.g" S3 F600
;
; Block terminators: dedent-based.

var mm   = 3.0
var feed = 600
if exists(param.S)
  set var.mm = param.S
if exists(param.F)
  set var.feed = param.F

G1 E{var.mm} F{var.feed}
