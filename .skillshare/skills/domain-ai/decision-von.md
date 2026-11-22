# AI · Decision · The Von transport and test stub

Files in `scenes/ai/decision/`: `decision_client.gd`, `decision_stub.gd`, `decision_server_launcher.gd`, `server_probe.gd`; for recorded Von in tests `von_key.gd`, `von_recording.gd`, `von_wire.gd`, `von_blocking_ask.gd`. The walk that calls them: `decision.md`.

## Client (`decision_client.gd`)

The planner's child; `DecisionPlanner.setup(tuning.decision)` builds it and configures it from `tuning.decision` (`server_url`, `model`: `NpcDecisionTuning` owns the endpoint and the model, the client keeps no defaults). `ask(state, instructions, options)` POSTs ONE `choice` question to `/v1/systemone`.

- `answered(pick, probabilities)` carries the argmax `choice` when it is an offered id, else the highest-probability offered id: a stale or foreign id can never be chosen. Von's distributions are flat, so taking the top pick rather than sampling keeps the NPC decisive.
- `failed()` fires for a request that could not start, a transport failure, a non-200, a malformed answer or no offered id. A transport failure and an HTTP error are reported as different faults: a 4xx/5xx prints the server's own `{"detail": …}` (`error_detail`, which the launcher's warning reuses), never "unreachable". An identical failure is logged once per client; a success clears that.
- The adopted-decision log line (`<NPC> (Von) COMBAT - Intruder - FLANK - …  [combat auto, combat 112ms, …]`) is the controller's.

## Test seam (`DecisionStub`)

While `DecisionStub.active`, `ask()` answers from the stub a frame later with no HTTP. `rules` is an ordered `[{ pick, question? }]` (the first rule whose id is offered and whose `question` text occurs in the level's question wins, else the first offered id); `fail` makes every ask fail (server down); `latency_frames` holds an answer back like a slow server while the NPC carries on with its old order; `requests` logs `{ state, question, options, pick }` per ask. Only the Testing domain sets these (`TestSetup.von_script(rules, latency_frames)` and `von_down()`; statics are restored after each test).

`DecisionStub.mode` picks who answers: `SCRIPT` (above, the default), `REPLAY`, `LIVE` or `RECORD`. A `requires_von` test gets REPLAY in a normal run, LIVE under `--include-von` / `--require-von`, RECORD under `--record-von` (`TestVonGate.mode_for`; a `live_only` test gets no stub and the async client).
- **REPLAY** answers from the test's `VonRecording` (`<name>_test.von.json`, written whole by RECORD). The `VonKey` is the state text, the question and the option descriptions sorted (Von is deterministic and blind to option order and id names), with the instance id inside option ids normalised (`VonKey.id_map`): a character's (`t_`, `lead_seen_`, `lead_heading_`, `lead_ally_`) to its spawn order (`WorldRng.order_of`), a `do_<object id>_<action>` to `do_<action>` (the object is dropped: its room is in the description); ids that then read alike are told apart by `~<rank>` of their description's sorted place. A recorded pick maps back to the offered id by that. An ask the recording lacks lands in `misses` and fails the test (`VonRun.problems`) naming the question and `tools/run_tests.sh --record-von --id=<id>`; there is never a silent pick.
- **The hold:** REPLAY, LIVE and RECORD deliver each answer exactly `hold_frames` (12, about 200 ms at 60 fps) physics frames after its ask; the NPC carries on with its old order meanwhile. LIVE and RECORD ask the server with a blocking `VonBlockingAsk` (the stalled main thread is the held sim, 10 s at most, then a fault that fails the test), so the three play the same frames.
- **RECORD** also adds each answer to the recording, saved when the test passes (or is GAP) and Von never faulted.
- Wording changes in the snapshot or a question change the key: every recording they touch goes stale and FAILs until `--record-von` rewrites it. Run it after such a change and commit the diff.

## Server launcher

`decision_server_launcher.gd` starts Von through the boot script of the OS, tells why when there is no server, and `tools/run_tests.sh` preflights a live run (`--require-von`, `--record-von`): when the Von venv is missing, its base Python is gone (`pyvenv.cfg` `home =`) or `von --version` fails, it stops before any test and prints which and the bootstrap command of the OS. All of it: `decision-von-server.md`.
