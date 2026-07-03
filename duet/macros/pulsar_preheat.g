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
; SETPOINT DELIVERY — the colon-list must be built as ONE string
; expression, not two adjacent substitutions:
;
;   BROKEN: G10 P0 S{var.nozzle}:{var.barrel}
;     RRF parses S{var.nozzle} as complete (215), then drops the
;     orphaned :{var.barrel}. A single S value gets broadcast to every
;     heater on the tool → both zones end up at the nozzle temp.
;     (Confirmed on Ric's Duet: echo showed 215/190 correct, but both
;     heaters heated to 215. The literal `G10 P0 S215:190` worked.)
;
;   WORKS: build "215:190" as one string, substitute once.
;     var.setlist = "" ^ nozzle ^ ":" ^ barrel  -> "215:190"
;     G10 P0 S{var.setlist} ...  expands to  G10 P0 S215:190 ...
;     which is byte-identical to the literal that worked.
;
; (Object-model writes — set tools[0].active[i] = ... — do NOT work
; either; the RRF object model is read-only from meta-commands.)
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

; Colon-list in tool-heater order (H1:0) = nozzle:barrel.
var setlist = "" ^ var.nozzle ^ ":" ^ var.barrel

echo "pulsar_preheat: setlist=" ^ var.setlist ^ " (nozzle:barrel)"

T0
G10 P0 S{var.setlist} R{var.setlist}
M116 P0

; Signal the UR that we're at temp. Will no-op until the DIO line is
; wired and the M42 in pulsar_signal_ready.g is uncommented. Absolute
; path because RRF 3.6 on this Duet doesn't auto-search /macros/.
M98 P"0:/macros/pulsar_signal_ready.g"
