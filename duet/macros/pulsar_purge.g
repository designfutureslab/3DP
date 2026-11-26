; pulsar_purge.g — prime the screw with a fixed purge extrude. BLOCKING.
;
; Usage:  M98 P"0:/macros/pulsar_purge.g" E<mm> F<mm_per_min>
; e.g.    M98 P"0:/macros/pulsar_purge.g" E200 F300
;
; Run once after preheat, before a job, to push out cold/degraded
; material and confirm clean flow. Meant to be driven from the separate
; preheat+purge routine (urscript/pulsar/preheat_purge.script) or a DWC
; button — NOT from the live print path.
;
; This one is deliberately BLOCKING: the trailing M400 waits for the
; purge move to physically finish, so RRF doesn't send its Telnet "ok"
; (and the UR routine doesn't advance) until the purge is actually done.
; That's the opposite of the daemon's short non-blocking chunks — a
; purge is a one-shot setup step, so waiting for it is correct.
;
; Does not touch global.pulsar_running, so it won't fight the daemon.
; Only run it while the daemon is idle (pulsar_running = false), i.e.
; before pulsar_start.g — otherwise the daemon's chunks and this move
; interleave.
;
; Block terminators: dedent-based (see daemon.g).

var mm   = 200
var feed = 300
if exists(param.E)
  set var.mm = param.E
if exists(param.F)
  set var.feed = param.F

echo "pulsar_purge: extruding " ^ var.mm ^ " mm at F" ^ var.feed

T0                        ; ensure Pulsar tool (drive) is current
M83                       ; relative extrusion
G1 E{var.mm} F{var.feed}
M400                      ; block until the purge move completes
