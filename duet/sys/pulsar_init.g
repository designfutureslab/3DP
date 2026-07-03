; pulsar_init.g — initialise the globals the daemon and macros depend on.
;
; Add this line to config.g (anywhere after the tool definition):
;   M98 P"pulsar_init.g"
;
; It is safe to re-run — every global is guarded with `if !exists`, so
; calling this twice won't reset values that have been changed at runtime.
;
; RESPONSIVENESS MODEL (see daemon.g and duet/README.md):
;   The screw is a stepper, so it only turns while G1 E moves are being
;   fed to it. daemon.g keeps it fed with SHORT chunks — short so that a
;   change to pulsar_feed, or clearing pulsar_running to pause, takes
;   effect within roughly one chunk (~0.3-0.8 s) instead of waiting out
;   a multi-minute move. All live control is done by setting these
;   globals directly over Telnet (fire-and-forget), which RRF processes
;   immediately because they're meta-commands, not queued motion.
;
;   pulsar_chunk : mm of E per daemon move. Smaller = snappier pause /
;                  rate response, but more loop iterations. 5 mm at
;                  F600 ~= 0.5 s/chunk. Drop toward 3 for snappier,
;                  raise for smoother if the screw stutters.
;   pulsar_feed  : F-value (mm/min). This IS the live rate/"flow" knob —
;                  set it to scale deposition without stopping the screw.
;
; pulsar_dwell is gone — daemon.g now computes the inter-chunk dwell from
; chunk and feed every iteration, so a live feed change re-paces itself
; instead of drifting against a stored dwell.
;
; Block terminators: RRF 3.6 rejects both bare `end` and `endif` with
; "Bad command: X" as of testing on Ric's Duet. This file uses
; dedent-based block termination — each `if` block ends at the next
; line at the same (or lower) indentation.

if !exists(global.pulsar_running)
  global pulsar_running = false
if !exists(global.pulsar_feed)
  global pulsar_feed = 600
if !exists(global.pulsar_chunk)
  global pulsar_chunk = 5
