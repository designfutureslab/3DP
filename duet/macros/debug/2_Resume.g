; Debug button — resume / start the screw at the current pulsar_feed.
;
; Same as the robot's pulsar_resume(). If feed is 0 for some reason,
; bump it to a sane default first so the daemon actually turns.

M98 P"0:/sys/pulsar_init.g"
if global.pulsar_feed <= 0
  set global.pulsar_feed = 600
set global.pulsar_running = true
echo "PULSAR resumed at feed=" ^ global.pulsar_feed ^ " mm/min"
