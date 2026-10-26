# Test probes and suites split by topic

With `max-file-length` (1000), `max-class-variables` (15) and `max-public-methods` (20) on, eight test files were over
(lines as `wc -l` counts them):
- seven static probes: `order_probe` (41 public), `slots_probe` (1325 lines, 39 public), `vehicle_probe` (36),
  `grenade_probe` (34), `entry_probe` (28), `follow_probe` (25) and `outfit_probe` (21);
- the native suite `door_stack_suite` (28 cases, public by gdUnit's contract).

Tests follow the game's rules (#76, decision 3): no exclusion, threshold or suppression.

A probe splits into the topics a test author looks up together. Each is a static library (`extends RefCounted`, all
`static func`), reached by a preload const in the same folder, never named by part number:

| Probe | Splits into |
|---|---|
| `order_probe` | `Order` (the squad, its orders, their radio, the clock, the back door's clicks) / `OrderBrain` (an NPC's brain read under an order) / `OrderMenu` (the command menu and the order markers on a player's screen) |
| `slots_probe` | `Slots` (the slot seam, a way in's frame, the world, the spec's numbers) / `SlotRules` / `SlotCapacity` / `SlotFaults` |
| `vehicle_probe` | `Probe` / `VehicleFrame` / `VehicleRide` |
| `grenade_probe` | `Probe` / `GrenadeSpec` / `GrenadeAi` |
| `entry_probe` | `Entry` / `EntryWatch` |
| `follow_probe` | `Follow` / `FollowWatch` |

`outfit_probe` (21 public) only privatises four members. A native suite splits by the module it pins:
`door_stack_suite` (16 cases, ids kept) and `stack_claim_suite` (12), their shared speakers and callouts in a fixture
probe of their own, `stack_radio_probe` (`StackRadio`), not copied.

The rules:
- **A member no other file calls is private** (ADR 0006's rule A, applied to a static library). Twenty-one went
  private (order 4, slots 8, vehicle 3, outfit 4, grenade 1, follow 1); one went public (`slots_probe`'s
  `_ray_to_edge`, now `SlotRules.ray_to_edge`, read from two files).
- **Moved names are kept**, so a caller changes only its const: `OrderBrain.brain`, `FollowWatch.watch`,
  `SlotFaults.point_faults`. Every call-site edit is then a const swap a reviewer can check, and the failure messages
  and skill lists that name them stay true.
- **The spec's numbers stay in the first file**, where tests read them, and a new file reads them through it
  (`Probe.BLAST_RADIUS`, `Slots.ROOM_INSET`, `Follow.OFF_SPOT`). Only a const with a sole user moves with it (the
  menu's script paths and panel numbers, `slots_probe`'s capacity grid).
- **No preload cycle:** each split is a DAG (`OrderMenu` → `Order` → `Entry`; `SlotCapacity` → `SlotFaults` →
  `SlotRules` → `Slots`), and no forwarder or alias is left behind.
- **Code moves; it is not rewritten:** every moved function is the original once its new receiver and underscore are
  undone, byte for byte but where the formatter rewrapped a line the longer receiver pushed past 100 columns.

## Consequences

**The counts** (lines / public, before → after; no file has a `var` but the inner classes `StackRadio.Speaker` (1)
and `VehicleRide.Hold` (4)):

| File | Before | After |
|---|---|---|
| `order_probe` | 751 / 41 | 233 / 17, + `order_brain_probe` 67 / 9, `order_menu_probe` 475 / 11 |
| `slots_probe` | 1325 / 39 | 176 / 7, + `slot_rules_probe` 295 / 13, `slot_faults_probe` 553 / 5, `slot_capacity_probe` 375 / 7 |
| `vehicle_probe` | 442 / 36 | 239 / 15, + `vehicle_frame_probe` 101 / 11, `vehicle_ride_probe` 114 / 7 |
| `grenade_probe` | 331 / 34 | 166 / 17, + `grenade_spec_probe` 51 / 5, `grenade_ai_probe` 130 / 11 |
| `entry_probe` | 466 / 28 | 276 / 17, + `entry_watch_probe` 196 / 11 |
| `follow_probe` | 355 / 25 | 188 / 14, + `follow_watch_probe` 176 / 10 |
| `outfit_probe` | 294 / 21 | 294 / 17 |
| `door_stack_suite` | 754 / 28 | 521 / 16, + `stack_claim_suite` 221 / 12, `stack_radio_probe` 36 / 2 |

gdstyle counts each file one line longer (the final newline's empty line). The largest new file,
`slot_faults_probe`, is about half the line limit.

**The callers:** 788 call sites in `tests/` changed only the const they call through (order 201, slots 37, vehicle
161, grenade 147, entry 98, follow 144), plus the two suites' 64 fixture calls (`_speaker` / `_callout` →
`StackRadio.speaker(self, …)` / `StackRadio.callout(…)`). No sandbox calls a probe. Where a longer receiver pushed
a line past 100 columns, the formatter or a hand wrap moved it; in two tests a read was taken into a local first so the
formatter's wrap left `run` within `max-nesting-depth` and `max-function-length` (`vehicle/launch_and_brake`,
`ai/movement/follow_top_up`).

**What stays the same:** every catalog test id (`tools/run_tests.sh --list`: the same 583 ids, plus the native suite
`ai/stack_claim_suite`), every test's verdict and failure message, and the whole suite's counts.

**The switch-on:** with the tree at zero findings under each, the three rules are on in `gdstyle.toml` at gdstyle's
defaults, one commit each (`max-public-methods`, `max-file-length`, then `max-class-variables`, which waited on ADR
0008's command menu, test browser window and coverage probe), each with its probe in `tools/test_log_gate.py`'s
`QUALITY_ON`: 18 quality rules on, five off by decision, and the empty "not yet" table gone.

**Further rule:** a probe that would grow past 20 public members or 1000 lines splits the same way: by topic, into a
sibling static library in its folder, its moved names kept.

**Deviations the build took** from the accepted design:
- `stack_radio_probe.callout`'s first parameter is `from`: `speaker` shadowed the probe's own `speaker` function,
  which the engine analyzer warns of.
- `VehicleRide` preloads `VehicleFrame` alone: nothing it holds reads `Probe`.
- `tests/perf/grenade_match_stress_test.gd` is a caller of `GrenadeAi.line_clear` that the design's commit table
  missed (its appendix counts it).
- The design counted twenty members privatised; the build privatised the twenty-one its own tables list.
- Each first file's header points to its new siblings, and comments in tests that named a moved member through its old
  const name the new one.

## Considered options

- **An exclusion of `tests/` from the three rules, or a higher threshold for it:** rejected by the user (#76,
  decision 3).
- **Instance-based probes** (a probe object per test, its methods grouped by property): rejected. It changes every
  test's first lines, and statics hold no state worth an object.
- **Topic consts for the spec's numbers too:** rejected. They would move about 200 reads for no limit.
- **Shorter names that drop the topic** (`OrderBrain.of`, `FollowWatch.run`, `SlotFaults.point`): rejected. Every call
  site would change its name as well as its const, and the names the failure messages and skills quote would go
  stale.
