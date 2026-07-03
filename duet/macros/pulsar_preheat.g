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
; So the colon-list order for S/R is  <nozzle>:<barrel>.
;
; Object-model writes (set tools[0].active[i] = ...) do NOT work — the
; RRF object model is read-only from meta-commands, so those lines threw
; and the macro aborted before heating anything. Back to G10, which is
; RRF's canonical "set this tool's heater temps" command.
;
; The echo line reports what we actually parsed so the DWC console shows
; the two values — a quick check that B and N came through distinct.
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

echo "pulsar_preheat: nozzle(H1)=" ^ var.nozzle ^ " barrel(H0)=" ^ var.barrel

T0
G10 P0 S{var.nozzle}:{var.barrel} R{var.nozzle}:{var.barrel}
M116 P0

; Signal the UR that we're at temp. Will no-op until the DIO line is
; wired and the M42 in pulsar_signal_ready.g is uncommented. Absolute
; path because RRF 3.6 on this Duet doesn't auto-search /macros/.
M98 P"0:/macros/pulsar_signal_ready.g"
