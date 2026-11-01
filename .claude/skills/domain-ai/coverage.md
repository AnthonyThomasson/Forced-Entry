# AI search coverage

How a searcher covers a room by sight: `scenes/ai/behavior/search_coverage.gd` (`SearchCoverage`, a `RefCounted` owned by `Behavior.errand` as `errand.coverage`). Tunables live in `tuning.coverage` (`scenes/ai/tuning/npc_coverage_tuning.gd`).

- A `look_around` move (search / explore) ignores the `arrive_room` early-out and walks INTO the room. On arrival `Behavior` calls `begin()`, then `step(delta)` each tick until it returns true and the task resolves. `max_commit_time` caps only the walk in.
- `begin` locks the room (`perception.confinement.room_at`) and grid-samples it, off the walls and off the navmesh holes, into `points`; `unseen` is the copy that shrinks. A point in no room samples nothing, so coverage ends at once.
- `step` drops every point now in view (`perception.sight.visible_points`: cone and line of sight), spends `budget`, eases the gaze toward the nearest unseen point (`look_rate`, from the actual facing, so a threat that held the eyes is not snapped back from) and walks to a new vantage when that point is farther than `approach` or behind furniture. It is done when `unseen` falls to `1 - target` of the points or the budget runs out.
- A shut door blocks sight (`docs/doors.md` DR5, DR14), so the room behind it has no point seen from outside and is not counted searched: the searcher walks in through the door as any walk does (`behavior-doors.md`) and covers the room from inside. Test `tests/ai/movement/door_in_the_way_test.gd`.
- `sample_room(key)` is public: the tactical entry measures how much of a room it saw from outside against the same grid, and reuses `begin`/`step` to clear the room once inside (`entry.md`).
- Read-outs: `debug()`; `Behavior.errand.debug_coverage()` adds `active`, which the search overlay draws (`debug.md`).
