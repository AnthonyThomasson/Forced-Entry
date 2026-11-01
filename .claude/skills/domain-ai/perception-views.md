# AI · Perception · Doorway views and the walked route (`agent_door_views.gd`, `perception_views.gd`)

E18 (`docs/tactical-entry.md`): a walk keeps out of the view out of every doorway into a room not yet clear, so an NPC does not stroll across a line a hostile may be watching. The behaviour's entry guard (`behavior_entries.gd`, `entry.md`) acts on what this part reports. Tunables: `tuning.entry_guard` (`door_view_depth`, `door_avoid_ratio`, `door_avoid_slack`, `pass_clear_time`); views are avoided only where `tuning.entry.enabled` and `tuning.entry_guard.enabled` are.

The perception builds one `AgentDoorViews`, hands it to its `AgentEntry` (`cuts_view` reads it) and to the snapshot. `AgentEntry.opening_id` / `normal_into` forward to it so the views never preload `agent_entry.gd`. `views` (the part) is the one perception part another sub-domain holds: `behavior/locomotion/loco_doors.gd` preloads `perception_views.gd` to type `doors.views`, which `Behavior.setup` hands over, and asks it `walk_route` and `walk_enters`.

## The view

`door_view(id, into, map, space)` is the polygon seen out of a doorway from inside room `into`: rays from the room's far corners through the opposite jambs, fanned from three points in the gap, stopped at the first wall (`AgentVision.wall_hit`: static bodies only, furniture and characters looked through; a standing door is one to the engine, so it ends a view, and a walker opens it, `behavior-doors.md`), cut at the edge of the room in front of a doorway between two rooms. Laid once per doorway on a baked map and kept.

`avoided(here_key, map, space, entering := "")` is the set a walk from room `here_key` keeps out of: every doorway into a room not *clear for passing* (`cleared_room` memory younger than `pass_clear_time`; `entry.is_cleared` stays the entry's own test), except the NPC's own room. With `entering` (`"<opening>><into>"`) that doorway's own view always counts. Worked out once per physics frame.

## The walked route

`AgentPerception.views.walk_route` returns the route the NPC actually walks: the plain one, unless it comes into one of those views (or, for an `entering` walk, goes into the room being entered), then the route on `NavBuilder.avoid_map` for the set. The avoid route is used if it reaches `to` and is no longer than `door_avoid_ratio` × plain + `door_avoid_slack`; failing that, with `entering`, the route round that doorway's own view and the room (`_entering_set`), capped the same unless `ordered_approach` (uncapped, D4). Result `{ map, path, len, plain_len, doors, pending, views }`; `pending` means the plain route crosses a view and the avoid map is still baking.

- `held` (D38): the walk belongs to a held stack's member, whose `entering` room is the one `confinement.keep_out` names. Every walk of that entry is then judged from the doorway's outer side (`_outside_of`, `_goes_in`), so a member standing in the doorway is not in the room yet. A walk not `held` is judged from where it stands, so from inside the room its plain way goes.
- `routes_ready()` / `warm`: the controller starts no decision until the avoid map of the NPC's room is baked (at most `WARM_CAP_MS` of game time), so the route bands a snapshot reads are the walked ones. `tests/ai/entry/entry_route_band_as_walked_test.gd`.

## The entry guard's reads

- `views.threshold_ahead(path, from_idx, max_dist)` → `{ opening, into, dist }` or {}: the first doorway whose wall plane a step crosses, heading into a room that is not the NPC's own and not cleared. The last step is extended so a destination that is the doorway counts. A member standing in a doorway of its `keep_out` room is read from the doorway's outer side.
- `views.passing_ahead(...)` (E15 / E18): the first doorway **view** the walk comes into from outside it (any doorway into a room not clear for passing, exterior doors too), not the NPC's own room nor a room the walk goes into by any of its doors (the entry into that room covers those).

## An ordered stack's walk (`docs/leadership.md` LD9, D4, D11, D20)

`views.ordered` (set each tick by the behaviour while it walks an ordered stack's way to its door) makes `sync_walks` switch the avoidance on for an NPC with `tuning.entry.enabled` off (a defender), and swap `pass_clear` for `_passable`, which also passes rooms the NPC stood in recently with no hostile sighting (`_seen_empty`). The room its stack holds counts as clear too (`_stack_room()`: the live order is a stack and a claim on its doorway under the same `order_id` is at `ready` / `bang`). An invader's walks are otherwise unchanged.

## Test seams

`tests/_ai/door_view_probe.gd`; `tests/ai/entry/` for the route-band and guard tests; `tests/ai/movement/npc_doors_walk_*` for the walk.
