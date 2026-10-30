---
name: domain-testing
description: Deep implementation detail for the Testing domain (scenes/testing/ + tests/) — game tests that declare a world (arena, hand-laid room layout or generated house), the actors and objects in it and which behaviours are on, run it, and assert what happened; plus the in-game test browser/runner, the gdUnit4 suites that the headless CLI runner (tools/run_tests.sh) and the editor's GdUnit panel run, and native pure-logic suites. Use when writing or debugging a test, adding a behaviour switch, running the suite, or editing scenes/testing/. Any engine error/warning during a test fails it. Complements the `architecture` skill (interface 13; the world is lit through interface 20).
---

# Testing domain (`scenes/testing/`, cases in `tests/`)

A second composition root beside `main.gd`. It builds a test's world **only through the published
interfaces** (WorldGen + its catalogue lookups, the Objects factories, the character scenes and controller
contract, EventBus and character signals) and never reaches into domain internals. Its world stage, its NPCs' binding, a declared
match or declared squads and the overlay routing go through the composition root's match builder (`MatchBuilder`, architecture
interface 23), the module Main builds its matches with, so a test world is staged, bound and populated as Main's match is.

## Running tests

- **Lint first:** every `tools/run_tests.sh` run starts with `tools/lint.sh` (about 14 s for the whole tree, nearly all of
  it the engine pass; skipped for `--list`,
  `--self-test`, with `--no-lint`, and when the sources are the ones the last clean lint saw: the wrapper
  keeps a fingerprint of HEAD plus every uncommitted change in `$TMPDIR`, so a rerun of an unchanged tree does not
  lint again, while any edit, new file or commit does). It loads every project script with the engine's debugger on, the only
  way a headless run reports GDScript analyzer warnings (unused variable or parameter, integer division, a name that
  shadows a member or built-in, a redundant `await` ...), and prints them per file; any warning ends the run with exit 1
  before a test starts. The engine names no line, so the report gives candidate lines, and the exact `line:col` of each
  integer division (it recompiles the script once per `/`). Then the project lint rules (`tools/lint_rules/`) and
  gdstyle (`tools/gdstyle.sh`, pinned v0.4.0; config `gdstyle.toml`): `gdstyle fmt --check` names every script the
  formatter would change, `gdstyle check` every finding of its rules (a line over 100 columns, tabs, member order,
  naming, ...: all errors but some `quality/*` ones, 18 on, among them the three structural ones,
  `max-file-length`, `max-class-variables` and `max-public-methods`, and five off by decision, as `gdstyle.toml`
  says); one finding fails the run like a warning. Run `tools/lint.sh scenes/x.gd`
  for one script and `tools/gdstyle.sh fmt scenes/x.gd` to format it. Fix the code: never silence a warning or a
  finding (see `audit`).
- **CLI:** `tools/run_tests.sh [filter words] [--include-von]` runs every test through gdUnit4's command-line tool:
  `godot --headless --fixed-fps 60 --log-file <dir>/godot.log -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd … -a <suites>
  -- --out=<dir> <the run's options>`. The suites are the wrapper suites (`tests/<domain>/<domain>_suite.gd`, one per AI
  topic folder `tests/ai/<topic>/<topic>_suite.gd`: 27, each running its folder's catalog tests as one case per test
  id) and the native unit suites (`*_suite.gd` extending `UnitSuite`); the options after `--` reach them
  (`test_batch.gd`), which pick the tests. gdUnit's own console goes to `<dir>/gdunit.txt`, not to the screen. A fresh
  checkout (no `.godot/` class cache) is imported first, since without it every script fails to parse. It prints one
  line per test (`PASS/FAIL/TIMEOUT/SKIPPED/GAP  <id>  (<sim s> sim, <ms> ms)`, failed checks indented with ✗), then a
  summary, and writes `report.json`; gdUnit's JUnit `results.xml` and HTML report land in `<dir>/gdunit/report_1/`.
  In gdUnit's terms FAIL and TIMEOUT are failures, SKIPPED and GAP are skipped (a GAP with the reason "gap: expected to
  fail" and its failed checks). Exit code 1 means a test failed or timed out, or an
  error/warning was logged outside any test. **GAP** is a test tagged `gap` (a behaviour written into a spec that the
  code does not show yet, left red on purpose) that failed or timed out: expected, printed with its failed checks and a
  bundle like a FAIL, counted apart in the summary and never a failure of the run; a `gap` test that *passes* is a FAIL
  ("drop the gap tag"). `tools/run_tests.sh gap` lists them (tag prefix); `--failed` and `--fail-fast` leave them out. Filter words are word prefixes over id, name, domain,
  description and tags (`ai` matches the ai domain, not "chair"). Sandboxes live apart in `sandboxes/` and are never run.
  `requires_von` tests are skipped unless `--include-von` is passed (`--require-von` runs them and
  fails when no server is live), and are then paced in real time
  (see below). The totals line names those skips apart from any other (their records in `report.json` carry `"von": true`): `69 skipped (69 need Von, not run:
  --require-von)` (with none, the line has no parenthesis), and it ends with the machine's 1-minute load, which a line before
  the first test prints too (each process's totals line and a sharded run's merged one alike). `--changed` ends with
  `NOTE <n> Von test(s) in the changed domains were not run: tools/run_tests.sh --domain=<d> --require-von` when the
  domains it ran hold Von tests it skipped; the run that covers them for a change to the AI is in the table below
  (`runner-flags.md`). Run
  with the Bash sandbox disabled, like every Godot launch.
- **Quiet by default:** the game's own log of what happens (shots, punches, house seed, Von decisions, the
  `PERF …` numbers) goes through `GameLog.say` (General), which a `run_tests.sh` run turns off; pass `--verbose` to
  see it (e.g. to read the `PERF` lines when re-baselining). Engine errors/warnings are never gated.
- **Selecting:** `--domain=NAME[,NAME]` (exact domain(s); the filter words are word prefixes, so `ai` also
  catches a test that mentions "aim"), `--id=ID[,ID]` (exact ids), `--failed` (wrapper only: the tests
  that FAILED / TIMED OUT in the previous run of this checkout, read from its merged report in `$TMPDIR`),
  `--list [words]` (id, von flag, tags; runs nothing; `scenes/testing/test_list.gd`). `--id`, `--domain` and
  `--skip-domain` given more than once add up, as one comma list (`--id=a --id=b` is `--id=a,b`), in the wrapper, the
  suites and `--list`. A run whose selection holds no test at all (catalog or native, every shard together) ends on
  `no test matched the selection: <args>` and exits 1; a `--list` that lists none, and a `--changed` with nothing
  mapped (`No changed file maps to any tests`) or mapped only to domains `--skip-domain` leaves out (`No test to run:
  the changed files map only to skipped domains (perf).`), exit 0. `--failed` when the last report holds no FAIL /
  TIMEOUT prints `no failed test in the last report: nothing to rerun` and exits 0, and over a report it cannot read
  exits 2. Domain/id selection is decided from the file path, so unselected test scripts are never loaded. A native
  suite runs whole or not at all: its id is its path under `tests/` (`general/weighted_pick_suite`), a case's
  `<suite id>::<function>`; `--domain`, `--skip-domain`, an `--id` naming the suite or one of its cases and filter
  words on its path and name select it, `--self-test` never.
- **Output:** `--summary` prints only non-passing tests and the totals; every run reports wall-clock ms
  per test (`wall_ms` in the report) and ends with a `Slowest:` line. `--verbose`, `--json` apply too.
- **Which command?**

  | Situation | Command |
  |---|---|
  | One test | `tools/run_tests.sh --id=<domain>/<name>` |
  | Just saw failures, fixed something | `tools/run_tests.sh --failed` |
  | Finished an edit | `tools/run_tests.sh --changed --summary` |
  | Before committing / big change | `tools/run_tests.sh --summary` (the whole suite shards over `auto` jobs by default: the free Godot slots of a machine-wide pool; the perf tests run after the shards, alone) |
  | Changed `scenes/ai/` or `scenes/testing/` | once `tools/run_tests.sh --domain=ai --require-von --summary` (why: `runner-flags.md`) |
  | Intermittent | `--id=<id> --repeat=10` (`--seed=N` pins the layout) |
  | A fixed test still red on the old code? | `tools/run_tests.sh --base=<rev> --id=<id>` (the working tree's tests against `<rev>`'s code, in a temporary worktree) |
  | Perf numbers to judge | `tools/run_tests.sh --domain=perf --quiet --summary` (waits for a quiet machine; judge only results not marked `loaded`: `perf.md`) |
  | What exists? | `tools/run_tests.sh --list [words]` |
  | Edited `scenes/testing/` | `tools/run_tests.sh --self-test` (`--changed` adds it) |
  | Show a person the change's tests in a window | `tools/play_tests.sh` (or `tools/play_tests.sh <id> …`) |
  | Run or debug a case in the editor | the GdUnit panel (below) |

- **`--self-test`:** runs the harness's own tests (`tests/_harness/`, `internal: true` in `describe()`;
  hidden from the browser and normal runs) through their own gdUnit suite, `tests/_harness/harness_suite.gd`, which
  only `--self-test` passes to gdUnit: verdict rules, catalog selection and shard partitioning, LogWatch really seeing
  engine logs, the statics restore pair (`static_restore_a` then `_b`, run in id order), and the probes
  `tools/test_log_gate.py` drives through environment variables (`verdict_probe`, `gap_probe`, `von_probe`,
  `warning_hold_probe`, `log_gate_probe`). Run it after editing `scenes/testing/`. `--changed` does this
  automatically when `scenes/testing/` changed.
- **Coverage:** `python3 tools/test_coverage.py` lists untested domains (a domain's tests counted in `tests/<domain>/**/*_test.gd`, its
  topic folders included), unused switches and interfaces no test calls.
- **Failures:** a FAIL/TIMEOUT prints each actor's final state and the `t.trace` series ranges, and writes
  `<out dir>/failures/<id>.json` (path printed as `bundle:`) with the full time-stamped event log, the
  final snapshot (actors, objects, and vehicles with their position, rotation and speed), traces and logged errors. See the `test-debug` skill.
- **More flags** (the per-run output dir, `--jobs` and the Godot slot pool with `GAME_TEST_JOBS`, perf after the shards, `--quiet`, `--base`, `--skip-domain` and the other flags, how `--changed` maps a changed file or a changed spec paragraph to tests, the test-seam env vars): `runner-flags.md`.
- **In a window** (the game's test browser, the headed and command-line queues, pause and overlays, locking interactions, `--shots`, `--windowed`): `in-game-runner.md`.

## The GdUnit panel (editor)

Running a case, a suite or everything from the editor's GdUnit dock, how it differs from `run_tests.sh` and its reports: `gdunit-panel.md`.

## Writing a test

**A behaviour is proved by a simulation test** (a `GameTest`: a declared world, run and asserted on, below).
Native gdUnit suites are for pure logic only and always supplement the simulation tests, never replace them: a native
suite may add fast checks of a pure function beneath the simulation test that proves the behaviour (see "Native unit
suites" below).

**No tautological tests.** A test exists to fail when the behaviour is wrong, so every assertion must be one the
code could get wrong:
- Expected values come from the spec (`docs/`, the ticket, the interface's description) or from what a player would
  see, never worked out the way the code does: no calling the function under test (or a helper it shares) to compute
  the expectation, no copying its formula, no reading its tuning constant back as the expected value (a probe keeps
  its own copy of the spec's numbers, as `door_view_probe.gd` does).
- It asserts an outcome the world shows (the shot landed, the health dropped, the NPC went in by the doorway), not
  that the code did what the test told it: a setter read back, a `von_script` pick reported as picked, a stub's answer
  echoed, a constant equal to itself, a node the test itself added found in the tree.
- A premise the asserts rest on is checked on its own, as a premise, and never counts as the test's proof.
- The check before keeping it: break the behaviour it covers (invert the condition, drop the call, zero the effect)
  and it must go red. A test that would still pass is rewritten or deleted, not kept for coverage.

One file `tests/<domain>/<name>_test.gd` that `extends GameTest`. Id = `<domain>/<name>`. A domain with many tests
splits them one folder deeper by topic (`tests/ai/entry/`, `flank/`, `gaze/`, `posture/`, `investigate/`, `combat/`,
`movement/`, `decision/`, `perception/`, `stack/`, `grenade/`, `debug/`: the overlays): the id is then `<domain>/<topic>/<name>`, the domain is still the first
folder (so `--domain=ai` and `--changed` see it), the descriptor's `category` is the topic and the browser shows a
row per topic under the domain. The file name keeps its topic prefix (`entry_waits_for_stack_test.gd`), the name
the specs quote.

**Sandboxes** (worlds you play by hand) are separate: `sandboxes/<name>_sandbox.gd`, same `GameTest` base, no assertions or timeout. `TestCatalog.discover_sandboxes()` lists them for their own browser section; `discover()` and the gdUnit suites never see them (`--play <words>` can still open one). They are `player_gun_range_sandbox.gd` ("Gun range": the player with every gun, 3 stun (7) and 3 frag (8) grenades re-armed through
`Character.inventory.set_loadout` 2 s after the last of its grenades goes off, which restocks the guns too (its `Restock` node), a dummy crouched behind a
couch to show cover (`CoverSpot`), and the armour range of nine dressed dummies to the south) and `vehicle_sandbox.gd` ("Vehicle yard": a walled concrete yard with the player, a car and a van, furniture to shove and three dummies; `nav.rebake` off, since rammed furniture would re-bake as overlapping holes). `sandboxes/showroom/` holds a ticket's temporary showroom (`ticket-assets`), deleted before its audit.

```gdscript
extends GameTest

func describe() -> Dictionary:
	return { "name": "Pistol shot wounds a target", "tags": ["pistol"], "timeout": 6.0 }

func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(600, 250))

func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"hit"), 2.0), "the shot lands"):
		return
	t.check(t.actor(&"target").health < 50.0, "the target lost health")
```

- **`describe()`** (all optional): `name`, `domain`, `description`, `tags` (the tag `gap` marks a test written
  before the behaviour exists: it is expected to fail and reports GAP, see "Running tests"), `timeout` (sim s, default
  10), `requires_von`,
  `fail_on_errors` / `fail_on_warnings` (default true), `allowed_logs` (regexes).
- **`configure(s: TestSetup)`** is data only, and the browser also calls it to list the switches.
  - Its whole API, one entry per part (world, objects, vehicles, actors, squads, a whole match, behaviour, scripted Von, presentation): `test-setup.md`.
- **`run(t: TestContext)`**, a coroutine. Always wait through `t`. A raw `await get_tree()…` can
  resume into a torn-down world.
  - Waits, all in sim time: `await t.seconds(s)`, `await t.frames(n)`,
    `await t.until(cond, timeout, msg := "") -> bool` (with `msg`, a timeout records a failed check).
  - Lookup: `t.actor(id)`, `t.puppet(id)` (the ScriptedController), `t.object(id)`, `t.vehicle(id)`,
    `t.controller(id, method)` (e.g. `&"current_act"` for an NPC brain; `TestContext.controller_of(character, method := &"control")`
    is the same for a character that is not a test actor, e.g. a match's NPC), `t.world`, `t.rooms`, `t.time`; off the world (a `TestWorld`, typed `Node2D` on the
    context, so a `var` takes an explicit type): `t.world.match_handle` (the declared match's handle, `{ world, house, rooms, openings,
    nav_debug, combatants, squads, player_stack, leader_overlay }`, {} with none), `t.world.squad(faction)` (the declared squad
    of that faction, `squads`' or the match's, null with none) and `t.world.player_stack` (the human leader's stack radio, null with none).
  - Event log: `t.events_of(topic, filter)`, `t.happened(topic, filter)`, `t.spawned(name_part)`.
    Topics are every EventBus topic (`&"hit"`: position, victim, attacker, direction, damage;
    `&"callout"`), `&"died"` / `&"hit_landed"` per actor (`actor` = its id; hit_landed adds body,
    damage, hand, −1 = shot), and `&"spawned"` / `&"removed"` for direct children of the world root
    (blood splatters and pools, debris, projectiles, dropped items).
  - `t.trace(name, value)` samples a number over time (a distance, a health) for the failure output.
  - Assertions: `check(cond, msg)` (soft), `require(cond, msg)` (ends the test; follow it with
    `if not …: return`), `expect_eq`, `expect_near`, `skip(why)`, and on its `verdict` part
    `t.verdict.expect_log(pattern, count)`. A test that asserts nothing fails.
- Puppet (`scripted_controller.gd`): `aim_at(node_or_point)`, `walk_to(point)` + `has_arrived()`
  (straight line, no pathing), `walk(dir)`, `set_run(on)` (holds run while moving), `set_posture(p)` (wants `stand` / `crouch`, written every frame like the AI does; `&""` stops asking), `stop()`, `select_slot(n)`, `punch()`, `kick()` (the leg kick), `shoot()` (one click), `hold_fire(on)` (hold the trigger: an automatic gun fires at its rate; a semi-auto one is unaffected), `reload()`,
  `interact(object, id)` (refusals land in `failed_interactions`), `end_interaction()`, `use_vehicle()` (one press of E: get in
  by the nearest usable door, or out; ignored by a character without a `use`) and `drive(throttle, steer, handbrake)` (holds the
  driving keys as the player's do: `movement.move_input` = `(steer, -throttle)` limited to length 1, `movement.run_input` = handbrake; `drive(0, 0, false)`
  lets go). Actions run on
  the character's next frame, and the character derives `facing` from the aim one frame later, so
  aim, wait a moment, then fire.
- Make randomness deterministic where the assertion depends on it (e.g. `projectile.flyover` off,
  since a character is partial cover).

### Native unit suites (pure logic only)

They supplement the simulation tests, never replace them: write the `GameTest` that proves the behaviour first, then,
if a pure function beneath it (no world, no nodes, no frames) earns fast edge-case checks, a native suite for it. One
file `tests/<domain>/<name>_suite.gd` that `extends UnitSuite` (`scenes/testing/unit_suite.gd`, a `GdUnitTestSuite`),
with `test_*` functions using gdUnit's own asserts (`assert_that`, `assert_int`, `assert_float`, ...;
`override_failure_message` says what broke). The example is `tests/general/weighted_pick_suite.gd`, General's
`WeightedPick`:

```gdscript
extends UnitSuite
## Native unit suite (pure logic) for General's `WeightedPick`, architecture interface 11: ...


func test_the_keys_take_their_stretches_in_their_order() -> void:
	_premise_zero_roll()
	assert_that(WeightedPick.key(_zero_roll(), { "b": 1.0, "a": 1.0 })).is_equal("b")
	assert_that(WeightedPick.key(_zero_roll(), { "b": 1.0, "a": 1.0 }, true)).is_equal("b")
```

- No tautologies (above): its expected values come from the spec (the interface's description), never worked out the
  way the code does; a premise the asserts rest on (here, that an rng at state 0 rolls 0.0) is checked on its own first.
- The log gate holds: an engine error or warning logged during one of its tests fails that test.
- `run_tests.sh` runs it in shard 0, ids `<path under tests/>::<function>` (`general/weighted_pick_suite::test_…`);
  `--changed` runs its domain when it or the domain's code changes; the GdUnit panel lists it like any suite.
- Name it `*_suite.gd`, never `*_test.gd` (that is the catalog's), and keep it out of the helper folders (`tests/_*`).

## Performance tests (domain `perf`, `tests/perf/`)

Writing, running or reading a performance test (the guards, their budgets, the 5v5 and 10v10 matches): `perf.md`.

## Tactical entry tests (tag `entry`)

Writing or debugging an `entry` test (`tests/ai/entry/`, `docs/tactical-entry.md`): the probes and the catalogue, with "Bodies in the way": `tests-entry.md`.

## Stack tests (tag `stack`)

Writing or debugging a `stack` test (the human's place in an AI stack, E16): `tests-stack.md`.

## Bodies in the way (issue #53)

Measuring a character walking into another (`tests/_ai/bump_probe.gd`): `tests-entry.md`.

## Leadership tests (tag `leadership`)

Writing or debugging a `leadership` test (`docs/leadership.md`): `tests-leadership.md`.

## Investigation tests (tag `investigate`)

Writing or debugging an `investigate` test (gunfire heard and answered): `tests-investigate.md`.

## Flanking tests (tag `flank`)

Writing or debugging a `flank` test (`tests/ai/flank/`): `tests-flank.md`.

## Outfit tests (tag `outfit`)

Writing or debugging an `outfit` test (`docs/outfits.md`): `tests-outfit.md`.

## Grenade tests (tag `grenade`)

Writing or debugging a `grenade` test (`docs/grenades.md`): `tests-grenade.md`.

## Lighting tests (domain `lighting`, `tests/lighting/`)

Writing or debugging a `lighting` test (`docs/lighting.md`): `tests-lighting.md`.

## Vehicle tests (domain `vehicle`, `tests/vehicle/`)

Writing or debugging a `vehicle` test (`docs/vehicles.md`): `tests-vehicle.md`.

## Errors and warnings fail the test (`log_watch.gd`)

A test failed on an engine error or warning, or you touch how the log is watched: `log-gate.md`.

## Behaviour switches (`test_switches.gd`)

One data table. A row maps a name to existing knobs:

- `actor: { child, props }` sets those props to `on` on that child of every actor (`child` `""` = the character itself), before it
  enters the tree; `controller: true` in place of `child` targets the actor's controller child (the one with `control`,
  interface 7, found by `TestContext.controller_of`), which is how every `ai.*` row reaches the NPC's tunables, a prop an indexed path
  (`tuning:<topic>:<name>`, set with `set_indexed`);
- `world: { node, props }` sets props on a world node;
- `static: [[Script, prop]]` sets that `static var` to `on`;
- `[Script, prop, off_value]` is for a non-bool knob: on keeps its tuning, off sets `off_value`.

Statics are restored after every test (`TestWorld.restore`). Current switches:

| Switch | What it controls |
|---|---|
| `ai.vision` | Whether NPCs can see. |
| `ai.callouts` | Team radio callouts, sent and heard. |
| `ai.pursuit` | Whether NPCs chase hostiles. |
| `ai.territory` | Defender confinement to the house. |
| `ai.hostile_on_sight` | Hostility toward anyone seen. |
| `ai.hostile_on_trespass` | Hostility toward anyone inside the house. |
| `ai.hostile_on_attack` | Hostility toward an attacker. |
| `ai.posture` | NPCs crouch while fighting in place (`tuning.pace.posture_enabled`). |
| `ai.entry` | Tactical entry (`tuning.entry.enabled`; on in the invader preset). |
| `ai.entry_guard` | The entry guard (`tuning.entry_guard.enabled`, on by default; needs `ai.entry`): any walk into an uncleared room goes in by entry. |
| `nav.rebake` | `NavUpdater.enabled`. |
| `audio.sound` | `SoundConfig.enabled`: shots, impacts, footsteps, reloads and the grenades' throw, bounce and burst make `sound` events and voices. |
| `physics.blood` | `BloodConfig.enabled`. |
| `physics.footprints` | `BloodPrintConfig.footprints_enabled`. |
| `physics.smear` | `BloodSmearConfig.enabled`. |
| `physics.debris` | `PhysicsConfig.debris_enabled`. |
| `physics.hit_particles` | `PhysicsConfig.hit_particles_enabled`. |
| `lighting.enabled` | `LightingConfig.enabled` and General's `LightMasks.shadows`: the dusk lighting (ambient, sky, piece lights and fixtures, flashes) and every occluder (walls, pieces, characters). The test world is lit like a match by default; a sandbox that lights itself turns it off. |
| `projectile.flyover` | `BallisticsFlightConfig.cover_flyover_scale`, 0 when off. A test that needs a chosen outcome instead pins `BallisticsFlightConfig.bullet_height` (0–100) with `set_static`. |

To add a switch, add a row. When the behaviour has no knob yet, add a master `static var` to that
domain's config holder, guarded at its one spawn point (the way `BloodConfig.enabled` gates
`BloodWound.record`).

## Files

Which file under `scenes/testing/` and `tests/` does what: `files.md`.

## Gotchas

- **A body added this frame is not in the physics space.** A direct-space query (a shape query, a ray) on the frame a body was added
  misses it: it joins the broadphase at the next physics step (`TestWorld` waits one after placing vehicles).
- **A click at a world point needs a still view.** The test camera (the runner's, or the gdUnit suite's) eases in from where the previous test left it
  (and keeps easing while the tree is paused), and an injected mouse event is handled a frame after it was aimed, so a click aimed while
  the view moves lands elsewhere: such a test first waits for the canvas transform to hold still (`OrderMenu.view_still`, `tests/_ai/order_menu_probe.gd`,
  used by `ui/command_menu_items` and the dock and overlay-bar tests). It counts drawn frames (`Engine.get_process_frames()`), not
  physics frames: the camera moves once a drawn frame, and a window's first frames run several physics frames each, so five still
  physics frames can pass before the camera has moved at all.
- **A test camera reads its screen centre only while current.** Godot updates `Camera2D.get_screen_center_position()` only for the
  viewport's current camera, and the test camera stays current: a test that adds its own camera and reads where it looks calls
  `make_current()` on it (`tests/general/camera_zooms_out_driving_test.gd`).

- **Von tests are paced in real time.** `run_tests.sh` runs use `--fixed-fps 60`, so the sim outruns the wall
  clock and game-time timers (HTTP timeouts, the launcher's probe interval) fire early. While a `requires_von` test is open the test session sleeps each frame to
  1/60 s, because `Engine.max_fps` is not honoured under `--fixed-fps` headless. A cold Von start
  takes about 5 s.
- A test that ends mid-wait (a failure or timeout) leaves its coroutine parked. Godot may report
  "ObjectDB instances leaked" at process exit for it. That happens after the last log poll and is
  harmless.
- An NPC thinks on its first tick, so the world must be live before actors enter: the world stage
  (`MatchBuilder.stage`) waits two physics frames after the walls and navmesh are made (otherwise an NPC sees through room walls and
  plans on an empty navmesh), then until `NavBuilder.ready` holds on the planning map and the steering map (the one rule for a map
  that has taken in this world's regions). A map's iteration is built on a worker thread: under load (parallel shards) its id and
  region list update before queries do, and an NPC that snapped a point onto the empty map walked to the origin. That wait is
  in real time, so the test clock is stopped while the world builds (`_building` in the test session).
- The defender preset is `tuning.hostility.on_trespass`, and an arena counts as its house. Turn
  `ai.hostile_on_trespass` off to test a reaction to something else.
