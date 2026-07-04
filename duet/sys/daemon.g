; daemon.g — Pulsar continuous-extrusion background task (v3, low-latency)
;
; RRF only re-invokes this file every few seconds, so we loop INTERNALLY
; with a `while` to keep the screw fed. No dwell between chunks —
; consecutive G1 E moves at the same feed blend in the planner into one
; continuous rotation (a G4 here executes as a queued STOP and causes a
; visible pulse; see git history).
;
; V3 CHANGES
;
; 1. TIME-BASED CHUNK SIZING. Chunk length is computed every iteration as
;      chunk_mm = feed(mm/min) / 60 × pulsar_latency(s)
;    so one chunk always takes ~pulsar_latency seconds REGARDLESS of the
;    current rate. With a fixed-mm chunk, latency ballooned at low rates
;    (2 mm @ F100 = 1.2 s) and shrank pointlessly at high rates. Now a
;    rate change / pause bites in roughly constant TIME across the whole
;    F150–F1200+ range. Default 0.25 s.
;
; 2. HARDWARE GATE (UR pause / e-stop). When global.pulsar_hw_gate is
;    true, the loop also requires the Duet input gpIn[0] (io1.in, wired
;    to a UR digital output configured "high while program running") to
;    read 1. Pausing the UR — or e-stopping it, which drops all UR
;    outputs — pulls the pin low and the screw stops within ~1 chunk,
;    with NO Telnet involvement (works even if the UR program is frozen).
;    Fail-safe: broken wire reads low = stop. pulsar_hw_gate defaults
;    FALSE so bench testing without the wire still works; flip it in
;    pulsar_init.g once wired.
;
;    The gate is level-based and self-resuming: UR resumes → pin high →
;    screw resumes at the current rate on the next loop check. If the pin
;    is low for you when it shouldn't be, check M409 K"sensors.gpIn".
;
; LATENCY BUDGET (why this is about as fast as Telnet+macros can go):
;   robot `set global...` over Telnet ~10-50 ms → RRF applies it
;   immediately (meta-command, not queued) → daemon re-reads globals next
;   iteration ≤ pulsar_latency s → planner look-ahead holds a small number
;   of ~latency-long chunks. End-to-end rate change ≈ 0.3–1 s; hardware
;   pause ≈ 1 chunk. The remaining floor is the planner queue depth —
;   if you need to inspect it on this build, run M122 and look at the
;   motion segment stats, or M409 K"move" F"v".
;
; Block terminators: dedent-based (this RRF rejects `end`/`endif`).
; The final G4 S0.2 at column 0 closes the while and is the idle tick.
;
; Globals (pulsar_init.g): pulsar_running, pulsar_feed, pulsar_latency,
; pulsar_hw_gate.

while exists(global.pulsar_running) && global.pulsar_running && global.pulsar_feed > 0 && (!global.pulsar_hw_gate || sensors.gpIn[0].value = 1)
  G1 E{global.pulsar_feed / 60 * global.pulsar_latency} F{global.pulsar_feed}
G4 S0.2
