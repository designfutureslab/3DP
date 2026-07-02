; pulsar_flow.g — set the extrusion flow multiplier.
;
; Usage:  M98 P"pulsar_flow.g" S<percent>
; e.g.    M98 P"pulsar_flow.g" S75
;
; S0 stops the bead cleanly without halting the screw (the daemon keeps
; queueing chunks; M221 S0 just pins the multiplier to zero).
;
; Block terminator: dedent-based.

var pct = 100
if exists(param.S)
  set var.pct = param.S

M221 S{var.pct}
