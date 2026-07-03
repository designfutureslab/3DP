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
; Object-model writes (set tools[0].active[i] = ...) do NOT work — the
; RRF object model is read-only from meta-commands, so those lines threw
; and the macro aborted before heating anything.
;
; G10 P0 S<nozzle>:<barrel> was tried next (RRF's tool-level "set both
; heater temps" command, using the H1:0 order from `M563 P0 ... H1:0`).
; Confirmed on this Duet: the echo showed nozzle=215/barrel=190 parsed
; correctly, but G10's colon list still broadcast 215 to both heaters —
; so we stop trusting the tool-level colon list and address each heater
; directly instead. M104 Hn Sn sets one heater's active temperature with
; no tool/list ambiguity at all.
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

M104 H0 S{var.barrel}
M104 H1 S{var.nozzle}
M116 H0
M116 H1

; Signal the UR that we're at temp. Will no-op until the DIO line is
; wired and the M42 in pulsar_signal_ready.g is uncommented. Absolute
; path because RRF 3.6 on this Duet doesn't auto-search /macros/.
M98 P"0:/macros/pulsar_signal_ready.g"
