; pulsar_preheat.g — set both zone targets and block until reached.
;
; Usage:  M98 P"pulsar_preheat.g" B<barrel_temp> N<nozzle_temp>
; e.g.    M98 P"pulsar_preheat.g" B190 N215   ; PLA
;         M98 P"pulsar_preheat.g" B220 N245   ; PETG
;
; B = barrel / feed zone target. Wired as heater H0 in config.g (labelled
;     "Top" — the upper zone closer to the hopper).
; N = nozzle / metering zone target. Wired as heater H1 (labelled
;     "Bottom" — the lower zone closer to the nozzle).
;
; The tool's heater list is `H1:0`, so when we hand M568 a colon-pair of
; setpoints, position 0 = H1 (nozzle), position 1 = H0 (barrel).
;
; Blocks via M116 until every heater on tool 0 is within tolerance.

var barrel = 190
var nozzle = 215
if exists(param.B)
  set var.barrel = param.B
endif
if exists(param.N)
  set var.nozzle = param.N
endif

M568 P0 S{var.nozzle}:{var.barrel} R{var.nozzle}:{var.barrel} A2
M116 P0

; Signal the UR that we're at temp. Will no-op until the DIO line is
; wired and the M42 in pulsar_signal_ready.g is uncommented.
M98 P"pulsar_signal_ready.g"
