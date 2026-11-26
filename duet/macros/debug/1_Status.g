; Debug button — report the Pulsar daemon state to the console.
;
; Temps are already live on the DWC dashboard; this shows the daemon
; globals you can't otherwise see at a glance.

M98 P"0:/sys/pulsar_init.g"
echo "PULSAR  running=" ^ global.pulsar_running ^ "  feed=" ^ global.pulsar_feed ^ " mm/min  chunk=" ^ global.pulsar_chunk ^ " mm"
