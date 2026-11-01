# AI locomotion: door leaves on a walk's way (`locomotion/loco_door_leaves.gd`, `docs/doors.md` DR14)

`loco_doors.gd` is the doorway VIEWS (`behavior-locomotion.md`); the house doors on a walk are `Locomotion.leaves`
(`DoorLeaves`, built once with it, holding it). The AI imports nothing of Objects: it finds a door by the group `doors` and reads
`gap()`, `is_down()`, `angle()`, `leaf_pose(0.0)`, `width`, `swing_into` and `latch_side_spot(from)` duck-typed (interface 24).

- **When.** Every walk of every primitive is a `move_to`, which asks `leaves.work(delta)` after `_check`. It reads the agent's path for
  the next `LOOKAHEAD` (90 px) and finds the first door whose doorway segment (`leaf_pose(0.0)`, `width`) the path crosses and that is an
  obstacle (`_no_obstacle` false): not down and not at its open stop, which it tells by `NavBuilder.leaf_in_map(door)` (interface 9: the
  maps carve a leaf there, so the walk already goes round it). An ajar door open enough to squeeze through is worked too (issue #183): its
  leaf stands across the doorway's mouth, which no map can carve, so a walk past it would run into it.
- **Working a door.** The walker goes straight to `latch_side_spot` (a spot already held by a known body nearer to it is queued behind,
  `QUEUE_BACK` 40 px out, until the door is no obstacle), stands within `SPOT_REACH` (20 px) of it; a leaf ajar on the far side is out of
  the character's reach from there, so it steps toward the leaf as it stands (`_leaf_nearest`) to `LEAF_STAND_OFF` (30 px) off it; then
  it uses the door with `character.use.doors.open_fully(door)` (never a toggle; once, again if the leaf stopped short: `TRIES` 2) and
  waits. Once the door is at its open stop, or down, the walk goes on and the door is left open. `Behavior.apply` runs `leaves.face()` after the watch stage
  so the door is in reach ahead (it turns the eyes only when the door is not).
- **Giving up.** A door still short of its stop after its tries is `refused` for `REFUSE_TIME` (45 s). Left open wide enough to pass
  (`gap()` at least the body's diameter + `PASS_MARGIN`, 6 px: `_passable`), it is no obstacle while refused and the walk goes through
  it as it stands; else the walk is `crowd.blocked`, so
  `Behavior._way_blocked` re-decides as for a held walk ("way blocked"). `leaves.redirect(dest)`, called from `_begin`, sends a walk whose
  plain route crosses a refused door by the middle of another opening of `perception.house.openings` (the nearest by route length
  whose two legs cross no refused door) before its destination; with no other way the walk stands short of the door and raises the blocked
  call every `REBLOCK_TIME`.
- **Elsewhere.** An entry's approach, cross and corner walks are `move_to` too: a shut door on one is opened by the member walking, the
  point man stopping at the latch side, opening it fully and going on (a stop-gap until #159: stack side, opener roles, cracking and
  breaching are not built); the pause is part of the phase's time. An entry whose doorway has a door that blocks sight (`leaves.shuts_view_at(middle)`:
  standing, `gap()` below its `width`, not `transparent`) skips its pie and crosses once the stack is ready, the skip decided by each member at its first look and kept (`pie.skipped`, set by `readiness._skips_pie`: the door the point opens does not bring the pie back for a split stack's other-side front man) (`entry.md`, `docs/tactical-entry.md` E3). A searcher walks into a room behind a shut door as any walk does:
  the door blocks sight (DR5), so that room has no point seen from outside and is not counted searched (`coverage.md`). A standing door
  ends a doorway view (`perception-views.md`).

Tests: `tests/ai/movement/door_open_leaf_walked_round_test.gd`, `door_ajar_opened_fully_test.gd`, `door_in_the_way_test.gd`, `door_blocked_rerouted_test.gd`, `door_second_walker_leaves_open_test.gd`; the pie at a door: `tests/ai/entry/entry_shut_door_skips_pie_test.gd`, `entry_ajar_door_skips_pie_test.gd`, `entry_glass_door_keeps_pie_test.gd`, `entry_open_door_keeps_pie_test.gd`, `entry_door_just_under_sixty_skips_pie_test.gd`, `entry_door_just_over_sixty_keeps_pie_test.gd`, `entry_knocked_down_door_keeps_pie_test.gd`, `entry_split_stack_shut_door_skips_pie_test.gd`, `entry_ajar_door_hostile_in_gap_test.gd` (their set-up is `tests/_ai/entry_door_probe.gd`).
