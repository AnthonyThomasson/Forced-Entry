---
name: domain-testing
description: Use when writing, running or debugging a game test, adding a behaviour switch, or editing scenes/testing/ or tests/.
---

# Testing domain (`scenes/testing/`, cases in `tests/`)

A second composition root beside `main.gd`. It builds a test's world only through published interfaces (WorldGen, the
Objects factories, the character scenes and controller contract, EventBus) and the root's `MatchBuilder` (interface 23),
so a test world is staged, bound and populated as Main's match is; it takes part in interface 13, lights the world
through 20 and gives the human its stack radio and squads through 17 and 21. A test is a `GameTest` (declared world, run,
asserted); the runner is gdUnit4: each folder's `*_suite.gd` wrapper plays that folder's tests as cases, native
`UnitSuite`s hold pure logic. Any engine error or warning during a test fails it.

File map: `files.md`. `tools/run_tests.sh` (its header documents every flag) drives gdUnit4 headless.

## Running tests

Run Godot with the Bash sandbox disabled. Every `run_tests.sh` run starts with `tools/lint.sh` (any finding ends the
run before a test starts; `--no-lint` skips it; `godot-run` holds the lint rules). It then prints one line per test
(`PASS/FAIL/TIMEOUT/SKIPPED/GAP`), a summary and writes `report.json` and, per failure, a `bundle:` JSON (`test-debug`).
Exit 1: a test failed or timed out, or an error or warning was logged outside any test.

- **Which command?**

  | Situation | Command |
  |---|---|
  | One test | `tools/run_tests.sh --id=<domain>/[<topic>/]<name>` |
  | Just saw failures, fixed something | `tools/run_tests.sh --failed` |
  | Finished an edit | `tools/run_tests.sh --changed --summary` (after a commit: `--changed=origin/main`) |
  | Before committing / big change | `tools/run_tests.sh --summary` (shards over the free Godot slots) |
  | Changed `scenes/ai/` or `scenes/testing/` | once `tools/run_tests.sh --domain=ai --require-von --summary` (`runner-flags.md`) |
  | Intermittent | `--id=<id> --repeat=10` (`--seed=N` pins the layout) |
  | A fixed test, still red on the old code? | `tools/run_tests.sh --base=<rev> --id=<id>` |
  | Perf numbers to judge | `tools/run_tests.sh --domain=perf --quiet --summary` (`perf.md`) |
  | What exists? | `tools/run_tests.sh --list [words]` |
  | Edited `scenes/testing/` | `tools/run_tests.sh --self-test` (`--changed` adds it) |
  | Show a person the change's tests | `tools/play_tests.sh [ids]` (`in-game-runner.md`) |
  | Run or debug a case in the editor | the GdUnit panel (below) |

- **GAP** is a test tagged `gap`: a behaviour a spec states and the code does not show yet, left red on purpose. It
  reports GAP and never fails the run; a `gap` test that passes FAILs ("drop the gap tag"). `tools/run_tests.sh gap`
  runs them (`--list gap` lists them).
- **Von:** `requires_von` tests skip unless `--include-von` (`--require-von` fails when no server is live). A Von test is
  paced in real time (see Gotchas).
- **Selection:** filter words are word prefixes over id, name, domain, description and tags (`ai` matches the ai
  domain, not "chair"); `--domain`, `--id` and `--skip-domain` accumulate. A native suite runs whole or not at all (id =
  its path under `tests/`, a case `<suite id>::<function>`).
- **Quiet by default:** the game's own log (`GameLog.say`) is off; `--verbose` shows it.
- **`--self-test`** runs the harness's own tests (`tests/_harness/`, `internal: true`, hidden from normal runs) through
  `tests/_harness/harness_suite.gd`. `python3 tools/test_coverage.py` lists untested domains, unused switches and interfaces no test calls.
- More flags and the Godot slot pool: `runner-flags.md`; which tests `--changed` picks for a file or a spec paragraph: `runner-flags-changed.md`. A window
  (browser, queues, `--shots`, `--windowed`, locking interactions): `in-game-runner.md`. Errors and warnings failing a
  test (`log_watch.gd`): `log-gate.md`.

## The GdUnit panel (editor)

The editor's GdUnit dock runs a case, a suite or everything; how it differs from `run_tests.sh`: `gdunit-panel.md`.

## Writing a test

**A behaviour is proved by a simulation test** (`GameTest`). Native suites are for pure logic and only supplement it.

**No tautological tests.** Every assertion is one the code could get wrong:
- Expected values come from the spec (`docs/`, the ticket, the interface), never worked out the way the code does: not
  by calling the function under test, copying its formula or reading its tuning constant back (a probe keeps its own
  copy of the spec's numbers, as `tests/_ai/door_view_probe.gd` does).
- Assert an outcome the world shows (the shot landed, the NPC went in by the doorway), never that the code did what the
  test told it (a setter read back, a `von_script` pick reported as picked, a stub's answer echoed).
- A premise the asserts rest on is checked on its own with `require`, and is no proof.
- Break the behaviour (invert the condition, drop the call) and the test must go red; one that stays green is rewritten.

One file `tests/<domain>/<name>_test.gd` that `extends GameTest`; id = `<domain>/<name>`. A domain with many tests splits
one folder deeper by topic (`tests/ai/entry/`): the id is `<domain>/<topic>/<name>`, the domain stays the first folder
(`--domain=ai` and `--changed` see it), `category` is the topic. The file name carries the topic prefix the specs quote.
Shared setup lives in `tests/_<domain>/*_probe.gd` / `*_maps.gd` helpers (not tests; `const X := preload(...)`).

**Sandboxes** (worlds you play by hand): `sandboxes/<name>_sandbox.gd`, the same `GameTest` base, no assertions or
timeout. `TestCatalog.discover_sandboxes()` lists them for the browser; `discover()` and the suites never see them. A
ticket's temporary showroom lives in `sandboxes/showroom/`.

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

- **`describe()`** (all optional): `name`, `domain`, `description`, `tags`, `timeout` (sim s; 10),
  `requires_von`, `fail_on_errors` / `fail_on_warnings` (default true), `allowed_logs` (regexes).
- **`configure(s)`** is data only (the browser lists its switches); API: `test-setup.md`.
- **`run(t)`** is a coroutine. Wait only through `t` (`seconds`, `frames`, `until`, all in sim time): a raw
  `await get_tree()…` can resume into a torn-down world. `t.check` is soft, `t.require` ends the test (follow it with
  `if not …: return`); a test that asserts nothing fails. The API: `test_context.gd`; the event log's topics are every
  EventBus topic plus `&"died"` / `&"hit_landed"` per actor and `&"spawned"` / `&"removed"` for the world root's direct
  children. `t.world` is typed `Node2D`, so a `var` off it takes an explicit type (`t.world.match_handle`,
  `t.world.squad(faction)`, `t.world.player_stack`).
- **Puppet** (`scripted_controller.gd`): its actions run on the character's next frame, and `facing` follows the aim
  one frame later: aim, wait, then fire. `use()` presses E (nearer of a door and a vehicle); `turn_door(steps)`
  is the wheel with E held.
- Make randomness deterministic where the assertion depends on it (`projectile.flyover` off: a character is partial cover).

### Native unit suites (pure logic only)

Write the `GameTest` that proves the behaviour first; if a pure function beneath it (no world, nodes or frames) earns
fast edge-case checks, add a suite: `tests/<domain>/<name>_suite.gd`, `extends UnitSuite` (`scenes/testing/unit_suite.gd`,
a `GdUnitTestSuite`), `test_*` functions with gdUnit's asserts. The example is `tests/general/weighted_pick_suite.gd`.

- Its expected values obey the no-tautology rules above; a premise (an rng at state 0 rolls 0.0) is checked first.
- The log gate holds per case. It runs in shard 0 (`runner-flags.md`); `--changed` runs its domain.
- Name it `*_suite.gd`, never `*_test.gd` (the catalog's), and keep it out of the helper folders (`tests/_*`).

## Performance tests (domain `perf`, `tests/perf/`)

Writing, running or reading a performance test (the standard, the guards, rendered vs headless): `perf.md`.

## Tests by topic

Read the file for the topic you write or debug; each holds that topic's probes and gotchas.

| Topic (tag) | File |
|---|---|
| tactical entry (`entry`), doorway views (`door_view`), bodies in the way, a match built as Main builds one | `tests-entry.md` |
| the human in an AI stack (`stack`) | `tests-stack.md` |
| leadership: orders, the squad, the menu, the ambush (`leadership`) | `tests-leadership.md` |
| leadership: following, the leash, the rally, held stacks, slots | `tests-leadership-follow.md` |
| investigation and hearing (`investigate`, `hearing`) | `tests-investigate.md` |
| flanking (`flank`) | `tests-flank.md` |
| outfits (`outfit`) | `tests-outfit.md` |
| the spectator inspector, detail card, overlay scope (domain `ui`) | `tests-ui.md` |
| grenades (`grenade`) | `tests-grenade.md` |
| lighting (domain `lighting`) | `tests-lighting.md` |
| the player's view (`vision`) | `tests-vision.md` |
| vehicles (domain `vehicle`) | `tests-vehicle.md` |

## Behaviour switches (`test_switches.gd`)

`s.switch(name, on)` flips a row of `test_switches.gd`'s table, which maps a name to existing knobs: `actor` props on a
child of every actor (`controller: true` reaches the NPC's controller, a prop an indexed path `tuning:<topic>:<name>`),
`world` props on a world node, `static` vars, or `[Script, prop, off_value]` for a non-bool knob. The file lists the
switches; a row's `default` applies when a test names no value (`vision.enabled`: off). Statics are restored after every test (`TestWorld.restore`); a test changes one with `set_static`, never by
assigning a config holder. To add a switch, add a row; when the behaviour has no knob, add a master `static var` to the
domain's config holder, guarded at its one spawn point (as `BloodConfig.enabled` gates `BloodWound.record`).

## Gotchas

A body added this frame, a click at a world point, a test camera, Von pacing, an NPC's first tick, the defender preset: `gotchas.md`.
