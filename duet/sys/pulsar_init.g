; pulsar_init.g — initialise the globals the daemon and macros depend on.
;
; Add this line to config.g (anywhere after the tool definition):
;   M98 P"pulsar_init.g"
;
; It is safe to re-run — every global is guarded with `if !exists`, so
; calling this twice won't reset values that have been changed at runtime.

if !exists(global.pulsar_running)
  global pulsar_running = false
endif

if !exists(global.pulsar_feed)
  global pulsar_feed = 900
endif

if !exists(global.pulsar_chunk)
  global pulsar_chunk = 1000
endif

if !exists(global.pulsar_dwell)
  global pulsar_dwell = 60
endif
