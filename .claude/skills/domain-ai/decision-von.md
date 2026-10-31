# AI · Decision · The Von transport, test stub and server launcher

Files in `scenes/ai/decision/`: `decision_client.gd`, `decision_stub.gd`, `decision_server_launcher.gd`, `server_probe.gd`. The walk that calls them: `decision.md`.

## Client (`decision_client.gd`)

The planner's child; `DecisionPlanner.setup(tuning.decision)` builds it and configures it from `tuning.decision` (`server_url`, `model`: `NpcDecisionTuning` owns the endpoint and the model, the client keeps no defaults). `ask(state, instructions, options)` POSTs ONE `choice` question to `/v1/systemone`.

- `answered(pick, probabilities)` carries the argmax `choice` when it is an offered id, else the highest-probability offered id: a stale or foreign id can never be chosen. Von's distributions are flat, so taking the top pick rather than sampling keeps the NPC decisive.
- `failed()` fires for a request that could not start, a transport failure, a non-200, a malformed answer or no offered id. A transport failure and an HTTP error are reported as different faults: a 4xx/5xx prints the server's own `{"detail": …}` (`error_detail`, which the launcher's warning reuses), never "unreachable". An identical failure is logged once per client; a success clears that.
- The adopted-decision log line (`<NPC> (Von) COMBAT - Intruder - FLANK - …  [combat auto, combat 112ms, …]`) is the controller's.

## Test seam (`DecisionStub`)

While `DecisionStub.active`, `ask()` answers from the stub a frame later with no HTTP. `rules` is an ordered `[{ pick, question? }]` (the first rule whose id is offered and whose `question` text occurs in the level's question wins, else the first offered id); `fail` makes every ask fail (server down); `latency_frames` holds an answer back like a slow server while the NPC carries on with its old order; `requests` logs `{ state, question, options, pick }` per ask. Only the Testing domain sets these (`TestSetup.von_script` and its second argument, `von_down`; statics are restored after each test).

## Server launcher (`decision_server_launcher.gd`)

A dev convenience, a root node of `main.tscn`: starts a local `von serve` when the game runs **from the editor** (never in exported builds) and stops it on exit. `von_path` defaults to the `application/von/server_path` project setting (blank: no auto-start). A server that can still **decide** on `port` is reused and left running. The port, host, path and model come from `NpcDecisionTuning`'s constants (`SERVER_PORT`, `SERVER_HOST`, `SERVER_PATH`, `MODEL`), the same ones the NPCs' `server_url` and `model` default to, so nothing is kept in step by hand. Every NPC shares the one server.

It runs at **scene load**, while the setup window is open, so the server gets its whole boot time before any NPC exists. Two choices keep that honest:

- A probe that is **refused** (nothing bound) launches at once; the retries (`probe_attempts`) pay off only for a probe that **times out** (a slow server worth reusing).
- The probe **POSTs a real decision** (`server_probe.gd`) instead of checking `GET /`, because an **orphaned server is worse than an absent one**: a `von serve` left by a hard-killed run has a dead stdout pipe, so its weight fetch dies on `EPIPE` for good while it keeps serving HTTP, and every decision comes back `422`. Asking it to decide catches that and resolves `false` with the server's `detail`. The probe doubles as a warm-up. After launching, the launcher polls its own server until the first answer and prints `[von] Decision server live on port N, Xs after scene load`: ready means a LIVE brain.

**`resolved(live)` + `is_resolved()`** is the gate contract (interface 22). It fires EXACTLY once, and every terminal path reaches `_resolve()`: server answered (`true`), or none is coming (`false`: exported build, blank `von_path`, failed spawn, `ready_timeout`, a server up that cannot decide). Any new terminal path MUST resolve, or the setup window hangs. `main.gd` awaits it before `start_match` so no NPC makes its first decision against a cold server (a run with no server still starts, with a warning, NPCs holding steady). Main checks `is_resolved()` *before* awaiting, because the exported-build path resolves synchronously in `_ready()` and children are readied before their parent. Output goes to `user://von_server.log` and echoes as `[von] …` lines.

Killing a Bash-launched Godot (`godot-run`) is a hard kill: `_exit_tree` does not run and the spawned Von server is orphaned on port 8000. Run `pkill -f "von serve"` after one.
