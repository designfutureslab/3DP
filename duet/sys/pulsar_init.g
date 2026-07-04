; pulsar_init.g — initialise the globals the daemon and macros depend on (v3).
;
; Called from config.g via  M98 P"pulsar_init.g"  — safe to re-run, every
; global is guarded with `if !exists` so live values aren't clobbered.
;
; V3 GLOBALS
;   pulsar_running : bool. While true (and gates pass) the daemon feeds
;                    chunks. Clear to pause. THE software on/off switch.
;   pulsar_feed    : mm/min. Screw speed = deposition rate = the ONE live
;                    knob. Set directly over Telnet. Must stay > 0 while
;                    running (pause via the flag, never feed=0).
;   pulsar_latency : seconds per chunk. The daemon sizes each chunk as
;                    feed/60 × latency, so control response time is
;                    ~constant across all rates. 0.25 s default. Lower =
;                    snappier but more meta-command overhead; below ~0.1 s
;                    the loop overhead starts to dominate.
;   pulsar_hw_gate : bool. When true, the daemon ALSO requires gpIn[0]
;                    (io1.in ← UR "program running" DO) to read 1.
;                    Default FALSE so the system runs without the wire.
;                    Set true here once the UR→Duet wire is in place.
;
; pulsar_chunk is GONE (v3) — chunk length is derived from feed × latency.
;
; Block terminators: dedent-based (this RRF rejects `end`/`endif`).

if !exists(global.pulsar_running)
  global pulsar_running = false
if !exists(global.pulsar_feed)
  global pulsar_feed = 600
if !exists(global.pulsar_latency)
  global pulsar_latency = 0.25
if !exists(global.pulsar_hw_gate)
  global pulsar_hw_gate = false
