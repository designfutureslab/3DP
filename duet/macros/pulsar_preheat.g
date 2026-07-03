; pulsar_preheat.g — set both zone targets and block until reached.
;
; Usage:  M98 P"0:/macros/pulsar_preheat.g" B<barrel_temp> N<nozzle_temp>
; e.g.    M98 P"0:/macros/pulsar_preheat.g" B190 N215   ; PLA
;         M98 P"0:/macros/pulsar_preheat.g" B220 N245   ; PETG
;
; B = barrel / feed zone target. Wired as heater H0, owned by tool 1
;     (labelled "Top" — upper zone, closer to the hopper).
; N = nozzle / metering zone target. Wired as heater H1, owned by tool 2
;     (labelled "Bottom" — lower zone, closer to the nozzle).
;
; History of what didn't work, see config.g's "Tools" section for the
; full story:
; 1. Object-model writes (set tools[0].active[i] = ...) — read-only from
;    meta-commands, threw and aborted before heating anything.
; 2. G10 P0 S<nozzle>:<barrel> with both heaters under one tool's H-list
;    — confirmed the colon list broadcasts a single value to every
;    heater the tool owns instead of splitting per heater.
; 3. Took H0/H1 off any tool, addressed via bare M104 Hn — commands
;    accepted with no error, but heaters never entered "active" state
;    and neither zone heated. Tool-less heaters don't activate.
;
; Fix: each zone now has its own single-heater tool (see config.g).
; G10 Pn Sn addresses a tool's heater without needing to T-select it
; first, and with only one heater per tool there's nothing to broadcast
; across.
;
; The echo line reports what we actually parsed so the DWC console shows
; the two values — a quick check that B and N came through distinct.
;
; Blocks via M116 until both heaters are within tolerance.
;
; Block terminators: dedent-based (RRF 3.6 rejects `end` and `endif`).

var barrel = 190
var nozzle = 215
if exists(param.B)
  set var.barrel = param.B
if exists(param.N)
  set var.nozzle = param.N

echo "pulsar_preheat: nozzle(H1)=" ^ var.nozzle ^ " barrel(H0)=" ^ var.barrel

G10 P1 S{var.barrel} R{var.barrel}
G10 P2 S{var.nozzle} R{var.nozzle}
M116 P1
M116 P2

; Signal the UR that we're at temp. Will no-op until the DIO line is
; wired and the M42 in pulsar_signal_ready.g is uncommented. Absolute
; path because RRF 3.6 on this Duet doesn't auto-search /macros/.
M98 P"0:/macros/pulsar_signal_ready.g"
