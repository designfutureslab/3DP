; Debug button — turn both heater zones off.
;
; Wraps pulsar_cooldown.g. Separate from Stop & Clear so you can stop the
; screw without losing your soak temperature between test runs.

M98 P"0:/macros/pulsar_cooldown.g"
echo "PULSAR heaters off (barrel + nozzle)."
