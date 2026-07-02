; pulsar_preheat.g — set both zone targets and block until reached.
;
; Usage:  M98 P"0:/macros/pulsar_preheat.g" B<barrel_temp> N<nozzle_temp>
; e.g.    M98 P"0:/macros/pulsar_preheat.g" B190 N215   ; PLA
;         M98 P"0:/macros/pulsar_preheat.g" B220 N245   ; PETG
;
; B = barrel / feed zone target. Wired as heater H0 in config.g
;     (labelled "Top" — upper zone, closer to the hopper).
; N = nozzle / metering zone target. Wired as heater H1 in config.g
;     (labelled "Bottom" — lower zone, closer to the nozzle).
;
; Tool 0's heater order per `M563 P0 ... H1:0`:
;   position 0 = H1 (nozzle)
;   position 1 = H0 (barrel)
;
; NOTE ON SETPOINT DELIVERY — we set active/standby setpoints directly
; on the tool object rather than via M568's colon-list `S<a>:<b>` form.
; With expression substitution, RRF's parser was observed to drop the
; second value and set both heaters to the first (barrel and nozzle
; both ended up at whatever the first slot's target was). Assigning
; tools[0].active[i] and tools[0].standby[i] one index at a time
; sidesteps that entirely.
;
; Blocks via M116 until every heater on tool 0 is within tolerance.
;
; Block terminators: dedent-based (RRF 3.6 rejects `end` and `endif`).

var barrel = 190
var nozzle = 215
if exists(param.B)
  set var.barrel = param.B
if exists(param.N)
  set var.nozzle = param.N

set tools[0].active[0]  = var.nozzle
set tools[0].active[1]  = var.barrel
set tools[0].standby[0] = var.nozzle
set tools[0].standby[1] = var.barrel

M568 P0 A2
M116 P0

; Signal the UR that we're at temp. Will no-op until the DIO line is
; wired and the M42 in pulsar_signal_ready.g is uncommented. Absolute
; path because RRF 3.6 on this Duet doesn't auto-search /macros/.
M98 P"0:/macros/pulsar_signal_ready.g"
