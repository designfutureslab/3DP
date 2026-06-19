; pulsar_retract.g — retract the extruder by a fixed amount.
;
; Usage:  M98 P"pulsar_retract.g" S<mm> F<mm_per_min>
; e.g.    M98 P"pulsar_retract.g" S3 F600
;
; Call after pulsar_flow.g S0 and before a travel move.

var mm   = 3.0
var feed = 600
if exists(param.S)
  set var.mm = param.S
end
if exists(param.F)
  set var.feed = param.F
end

G1 E-{var.mm} F{var.feed}
