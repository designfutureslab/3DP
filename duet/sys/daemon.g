; daemon.g — Pulsar continuous-extrusion background task
;
; RRF auto-runs this file in a loop. Each iteration completes, then RRF
; restarts it. While global.pulsar_running is true, we queue one SHORT
; extrusion chunk and dwell for slightly less than its execution time, so
; the next chunk arrives just before the current one drains — the screw
; runs continuously with only ~1 move queued ahead.
;
; WHY SHORT CHUNKS (see pulsar_init.g / duet/README.md):
;   The screw is a stepper — it only turns while G1 E moves feed it, so
;   "always running" means "always being fed short moves". Keeping the
;   move short and the queue ~1 deep is what makes live control fast:
;   a change to global.pulsar_feed re-paces on the next iteration, and
;   clearing global.pulsar_running pauses within ~one chunk instead of
;   waiting out a long queued move. The robot sets those globals directly
;   over Telnet (immediate meta-commands), so there's no M221/queue lag.
;
;   Dwell is computed here from chunk and feed every iteration rather
;   than read from a stored global, so a live feed change stays paced.
;   The 0.9 factor issues the next chunk just before the current one
;   finishes (queue depth ~1, no gap → continuous motion).
;
;   pulsar_feed must always be > 0 while running (it divides the dwell).
;   Pause is done by clearing pulsar_running, never by setting feed to 0
;   — so the running branch below only ever sees a positive feed. The
;   guard `if global.pulsar_feed > 0` makes that explicit and dodges a
;   divide-by-zero throw if a bad value ever slips through, without
;   relying on a max()/min() meta builtin whose availability on this
;   RRF build we haven't verified.
;
; Block terminator: dedent-based (RRF 3.6 on Ric's Duet rejects both
; bare `end` and `endif` with "Bad command: X"). The else branch runs
; to EOF, which implicitly closes the block.
;
; Tuning is held in globals (set by pulsar_init.g / pulsar_start.g):
;   pulsar_running  — bool, true while the daemon should feed chunks
;   pulsar_feed     — F-value (mm/min); the live rate/"flow" knob
;   pulsar_chunk    — mm of E per chunk (short = more responsive)

if exists(global.pulsar_running) && global.pulsar_running && global.pulsar_feed > 0
  G1 E{global.pulsar_chunk} F{global.pulsar_feed}
  G4 S{global.pulsar_chunk / global.pulsar_feed * 60 * 0.9}
else
  G4 S0.2
