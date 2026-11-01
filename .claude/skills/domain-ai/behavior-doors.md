# AI locomotion: door leaves on a walk's way (`locomotion/loco_door_leaves.gd`, `docs/doors.md` DR14)

`loco_doors.gd` is the doorway VIEWS (`behavior-locomotion.md`); the house doors on a walk are `Locomotion.leaves`
(`DoorLeaves`, built once with it, holding it). The AI imports nothing of Objects: it finds a door by the group `doors` and reads
`gap()`, `is_down()`, `angle()`, `leaf_pose(0.0)`, `width`, `swing_into` and `latch_side_spot(from)` duck-typed (interface 24).

- **When.** Every walk of every primitive is a `move_to`, which asks `leaves.work(delta)` after `_check`. It reads the agent's path for
  the next `LOOKAHEAD` (90 px) and finds the first standing door whose doorway segment (`leaf_pose(0.0)`, `width`) the path crosses and
  whose `gap()` is below the body's diameter + `PASS_MARGIN` (6 px).
- **Working a door.** The walker goes straight to `latch_side_spot` (a spot already held by a known body nearer to it is queued behind,
  `QUEUE_BACK` 40 px out, until the door is passable), stands within `SPOT_REACH` (20 px) of it, uses the door with
  `character.use.doors.open_fully(door)` (never a toggle; once, again if the leaf stopped short: `TRIES` 2) and waits. Once `gap()` is
  enough, or the door is down, the walk goes on and the door is left open. `Behavior.apply` runs `leaves.face()` after the watch stage
  so the door is in reach ahead (it turns the eyes only when the door is not).
- **Giving up.** A door still short after its tries is `refused` for `REFUSE_TIME` (45 s) and `crowd.blocked`, so
  `Behavior._way_blocked` re-decides as for a held walk ("way blocked"). `leaves.redirect(dest)`, called from `_begin`, sends a walk whose
  plain route crosses a refused door by the middle of another opening of `perception.house.openings` (the nearest by route length
  whose two legs cross no refused door) before its destination; with no other way the walk stands short of the door and raises the blocked
  call every `REBLOCK_TIME`.
- **Elsewhere.** An entry's approach, cross and corner walks are `move_to` too: a shut door on one is opened by the member walking, the
  point man stopping at the latch side, opening it fully and going on (a stop-gap until #159: stack side, opener roles, cracking and
  breaching are not built); the pause is part of the phase's time. A searcher walks into a room behind a shut door as any walk does:
  the door blocks sight (DR5), so that room has no point seen from outside and is not counted searched (`coverage.md`). A standing door
  ends a doorway view (`perception-views.md`).

Tests: `tests/ai/movement/door_in_the_way_test.gd`, `door_blocked_rerouted_test.gd`, `door_second_walker_leaves_open_test.gd`.
