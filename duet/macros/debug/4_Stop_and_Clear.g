; Debug button — full stop & clear. THE panic button.
;
; Stops the daemon, drains the queue (M400), zeroes flow, releases the
; extruder motor. Heaters stay ON so you can restart quickly — hit the
; Cooldown button separately if you want them off. This is exactly what
; pulsar_stop.g does at the end of a print, so it's safe to hit any time.

M98 P"0:/macros/pulsar_stop.g"
echo "PULSAR stopped: daemon off, queue drained, flow 0, motor released."
