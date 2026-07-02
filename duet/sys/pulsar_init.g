; pulsar_init.g — initialise the globals the daemon and macros depend on.
;
; Add this line to config.g (anywhere after the tool definition):
;   M98 P"pulsar_init.g"
;
; It is safe to re-run — every global is guarded with `if !exists`, so
; calling this twice won't reset values that have been changed at runtime.
;
; Block terminators: RRF 3.6 rejects both bare `end` and `endif` with
; "Bad command: X" as of testing on Ric's Duet. This file uses
; dedent-based block termination — each `if` block ends at the next
; line at the same (or lower) indentation.

if !exists(global.pulsar_running)
  global pulsar_running = false
if !exists(global.pulsar_feed)
  global pulsar_feed = 900
if !exists(global.pulsar_chunk)
  global pulsar_chunk = 1000
if !exists(global.pulsar_dwell)
  global pulsar_dwell = 60
