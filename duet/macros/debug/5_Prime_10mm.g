; Debug button — manually extrude 10 mm to prime / clear the nozzle.
;
; Stops the daemon first so it doesn't fight the manual move, then pushes
; a fixed 10 mm at a gentle rate. Zones should be at temp before using
; this (M302 P1 in config allows cold extrusion, but pushing cold pellets
; will just stall the screw). Hit it repeatedly to purge more.

M98 P"0:/sys/pulsar_init.g"
set global.pulsar_running = false
M400
T0
M83
G1 E10 F300
echo "PULSAR primed 10 mm"
