# Files: `scenes/testing/` and `tests/`

| File | Role |
|---|---|
| `game_test.gd` (`GameTest`), `test_setup.gd` (`TestSetup`) | The test base class and its declarative builder (`test-setup.md`). |
| `test_context.gd` (`TestContext`, an `Object`) | What `run(t)` calls. Two parts, each a `RefCounted` holding nothing of the context: `verdict` (`test_verdict.gd`: checks, logs, `conclude` → PASS / FAIL / TIMEOUT / SKIPPED, GAP for a `gap` test that failed as expected) and `bundle` (`test_bundle.gd`: what a failed run's bundle carries, `screenshot`, `snapshot`). The session frees it at close, which discards any test coroutine still parked on it. |
| `test_world.gd` | Builds a `TestSetup` into a sub-tree: statics and switches first, then house / layout / arena with its objects, then the world stage as Main's match has it (`MatchBuilder.stage` with `wait_nav`), vehicles, actors (each NPC bound by `MatchBuilder.bind_npc` before `_ready`), a declared match or squads, then world switches. No bake, light, nav-wait or bind code of its own. Exposes `restore()`, `set_overlay()` (through `MatchBuilder.set_overlay`), `set_overlay_scope(scope)` (`defenders`, `invaders` or `all`, through `MatchBuilder.set_overlay_scope`, kept for later `set_overlay`s and for actors spawned after it), `squad(faction)`. |
| `arena_builder.gd`, `layout_builder.gd` | The walled arena and the hand-laid layout, built through `FloorFactory` / `WallFactory` and annotated like a house (`WorldGen.annotate_layout`). |
| `scripted_controller.gd` | The puppet controller. |
| `test_switches.gd` | The switch table. |
| `log_watch.gd` | The log tail (`log-gate.md`). |
| `test_catalog.gd` | `discover`, `describe`, `matches`, and the CLI selection helpers `csv()` / `shard()` / `load_costs()`. |
| `test_session.gd`, `test_von_gate.gd` | Plays one catalog test at a time, shared by the runner and the gdUnit suites: builds its `TestWorld`, ticks its sim clock and timeout, routes the log to it, returns the verdict record. The `von` part (`test_von_gate.gd`) waits for the Von server and paces a Von test in real time. |
| `game_test_suite.gd` (`GameTestSuite`) | The gdUnit4 base of the wrapper suites: `cases(folder)` lists a folder's selected ids as one parameterized test's cases, `run_case(id)` plays one through a `TestSession`; restores and frames the runner window. |
| `unit_suite.gd` (`UnitSuite`) | The gdUnit4 base of a native pure-logic suite: the log gate per test, selected whole or skipped. |
| `test_batch.gd` | What one gdUnit run shares (static): its options (after `--`), the selection and shard, native-suite selection, the verdict records, the summary and `report.json`. |
| `test_report_hook.gd` | gdUnit's session hook (`project.godot`, `gdunit4/hooks/session_hooks`): starts and finishes a run given `--out`, makes each native case a record, steps the editor's runner. |
| `test_list.gd` | `run_tests.sh --list`. |
| `test_runner.gd` / `.tscn` | The in-game runner over a `TestSession`: interactive (`--play`, the browser's Play) and queued (`--queue`, Run N checked). No batch mode: batch runs are gdUnit's (`in-game-runner.md`). |
| `test_browser.gd` / `.tscn` | Hosts the UI browser window. |
| `decision_stub.gd`, `decision_budget.gd` (both in `scenes/ai/decision/`) | `DecisionStub`: the scripted-Von statics a `TestSetup` turns on, restored after each test; `DecisionBudget.per_frame` is set with `set_static` the same way. |
| `tests/**/<x>_suite.gd` | The wrapper suites (`extends GameTestSuite`, one parameterized test listing `cases("<folder>")`), `tests/_harness/harness_suite.gd`, and the native suites (`extends UnitSuite`). |
| `sandboxes/*_sandbox.gd` | Worlds played by hand, the same `GameTest` base. `player_gun_range_sandbox.gd` ("Gun range") is a `layout` of its `range` room and, built onto the outside of its north wall, four small rooms with seven doors in 60 px doorways, one of each catalogue door, a floor label by each door onto the range and a dummy behind the glass-panel one (a `layout`, not an `arena`: the two cannot be combined); `vehicle_sandbox.gd` is the vehicle yard. |
