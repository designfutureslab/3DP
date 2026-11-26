; Debug button — pause the screw (leaves everything else as-is).
;
; Same as the robot's pulsar_pause(). The screw coasts to a stop once
; the already-queued chunks drain (a few mm at the default chunk). Resume
; with the Resume button.

M98 P"0:/sys/pulsar_init.g"
set global.pulsar_running = false
echo "PULSAR paused"
