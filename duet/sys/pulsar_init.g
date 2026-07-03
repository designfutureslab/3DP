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
;   fed to it. daemon.g keeps it fed by looping over SHORT chunks with NO
;   dwell between them, so consecutive moves blend into one continuous
;   rotation (no stop = no pulse). Live control is done by setting these
;   globals directly over Telnet (fire-and-forget), which RRF processes
;   immediately because they're meta-commands, not queued motion.
;
;   pulsar_chunk : mm of E per daemon move. With no dwell, the look-ahead
;                  queue fills a few chunks deep, so this ALSO sets how
;                  much extrusion is committed ahead of a pause/stop
;                  (queue depth × chunk). SMALL keeps that bounded — 2 mm
;                  is a good default. Raise only if very short moves make
;                  the screw hiccup.
;   pulsar_feed  : F-value (mm/min). This IS the live rate/"flow" knob —
;                  set it to scale deposition without stopping the screw.
;
; No pulsar_dwell and no G4 in the loop — see daemon.g for why the dwell
; was removed (it was a queued stop, not a pacing sleep, and caused the
; pulse). The loop self-paces by blocking on G1 when the queue is full.
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
  global pulsar_chunk = 2
