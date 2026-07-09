; Debug button — report the Pulsar daemon state to the console (v3).
;
; Temps are already live on the DWC dashboard; this shows the daemon
; globals and the hardware-gate input you can't otherwise see at a glance.

M98 P"0:/sys/pulsar_init.g"
echo "PULSAR  running=" ^ global.pulsar_running ^ "  feed=" ^ global.pulsar_feed ^ " mm/min  latency=" ^ global.pulsar_latency ^ " s/chunk"
echo "  hw_gate enabled=" ^ global.pulsar_hw_gate ^ "  gpIn0(UR running)=" ^ sensors.gpIn[0].value
