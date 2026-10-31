# Briefs 1a, 1b, 1c: dead code and orphaned mechanisms

Workers 1a and 1b.

`coverage.txt`, when Phase 0 has one, is the runtime half of the evidence; how to read its tags and trust checks (a
Von-starvation warning in its header voids its combat zeros) is `ticket` (`refactor.md`), steps 2 and 4. Zero hits means not
run in the sample, never unreachable: each row is a lead, confirmed by hand like a scan hit.

## 1a. Unreferenced symbols

`python3 -I tools/audit_scan.py dead`: matches by token (a same-named member elsewhere hides a dead one: grep the qualified
name); any non-comment token in `scenes/ tests/ tools/ addons/` or a `.tscn` counts. Also check scripts nothing references,
`uids.txt`, the gaps in `test_coverage.txt` worth filling, and `coverage.txt`'s `dead` rows (never run, never referenced: the
strongest lead) and `test-only` rows.

**Every hit is advisory until confirmed by hand.** Dynamic dispatch no scan follows:
- **Duck-typed controllers:** any node with `control(character, delta)`; the match HUD and command server probe
  `current_act()` / `debug_status()` / `debug_state()`.
- **`Expression` eval:** `general/command_server.gd` evaluates GDScript from `tools/gcmd.py`; anything reachable from a verb
  is live.
- **Scene-wired signals and exported `NodePath`s** live in the `.tscn`.
- **Contract methods:** `get_surface()`, `take_hit()`, `get_interactions()`, `apply_impulse()`, `get_mass()`.

Grep the `.tscn` files and `tools/` for the bare name before proposing a deletion, and name which mechanism you ruled out. A
documented published method with no caller is still a finding: the doc or the method goes.

## 1b. Orphaned mechanisms (the valuable category)

A producer whose consumer is gone: trace who writes it and who still reads it. (`dead` counts an emitted signal as used, so
a signal nobody connects only shows here.) Run `audit_scan.py signals`, `facts` (snapshot facts no tree node gates on) and
`events` (each EventBus topic's listeners and payload keys).

- `coverage.txt`: `untriggered system` rows (referenced, never ran) and `dead branch` rows (an arm a live function never
  takes; an impossible condition is also Brief 2's dead branch).
- `signals`: a signal with no listener (`test_context._never` is a deliberate `await` sentinel).
- `facts`: facts `agent_snapshot.gd` writes that no tree `requires`, entry rule, test or tool names, marked documented
  (vocabulary in `domain-ai` (`perception.md`) or `docs/cover-and-stance.md`: a judgement call, report as such) or not (an
  orphan).
- By hand: grep the symbols that make it *work* (keys a consumer reads, connections, an enable flag), not its name; all
  matches in the producing file = orphan. Candidates: a dict field written but never read, a record key no handler reads, a
  cache or log nothing queries. Unread `behavior.gd` `debug_state()` keys are read via `gcmd`: mention only.

## 1c. Vestigial configuration (worker 1b)

An `@export`, `const` or `project.godot` setting nothing branches on (it looks like a working control). Check the config
holders (`BallisticsFlightConfig`, `PhysicsConfig`, `CharacterPostureConfig`, `BloodConfig`, `SoundConfig`, …) and controller
exports for values only passed along; `dead` already catches unread ones.

