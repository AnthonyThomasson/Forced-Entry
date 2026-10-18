---
name: domain-ai-perception
description: Deep implementation detail for the AI PERCEPTION sub-domain (scenes/ai/perception/) — what an NPC knows and how it is worded for Von. The sight sense, hostility rules, the generic event memory (with keyed supersede), movement tracks/facing/visible wounds, gunfire and footsteps heard, where shots came from, allies' radio callouts, the live grenades known (seen, heard, called, own) and the plan to get clear of them, a blinded or deafened NPC, leads, searched rooms, the tactics geometry (flank sides, fire/advance/retreat spots, route length + exposure, cover), the doorway geometry for tactical entry (agent_entry.gd: stack slots, pie arc, hard/soft corners, the team's slot claims) and its hand-off to the decision SNAPSHOT (the snapshot itself, its wording rules and option groups are the sub-domain `domain-ai-snapshot`). Use when editing scenes/ai/perception/ (except the snapshot) or working on vision, memory/eviction, hostility, flanking geometry, entry geometry, callouts, or combat line-of-sight. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Perception sub-domain (`scenes/ai/perception/`)

The SENSE half of the NPC brain: it turns the world into what the NPC *knows*, and turns that into the
snapshot the decision planner walks. It holds no policy — it never decides, picks or gates by goal. It
owns eight internal modules and presents one public face, `agent_perception.gd` (a `Node`).

Files:
- `agent_perception.gd` — the public face: SEE (observe), the contacts view, event intake, and the
  BUILD entry (`sense`) that gathers knowledge and delegates to the snapshot author.
- `agent_vision.gd` — the sight sense and the single owner of the ray query (`blocked` / `raycast`).
- `agent_hostility.gd` — the hostility rules (categorization).
- `agent_memory.gd` — a generic, behaviour-agnostic event log.
- `agent_tactics.gd` — combat geometry: flank sides, fire/advance/retreat spots, routes, cover.
- `agent_grenades.gd` + `agent_throw.gd` — the live grenades the NPC knows of and the plan to get clear of them, and the grenade geometry both that and the GRENADE tactic use (below).
- `agent_suspicion.gd` — why a room is suspect (`docs/grenades.md` G18): `rooms_suspected(rooms, lost, callouts)` -> room key -> reason ids in
  `ORDER` (`gunfire`, `footsteps`, `shot_from`, `ally_fight`, `seen_in`, `lost_by_door`, `heading_in`), `lost_rooms`, `shot_rooms` (the rooms `shot_line` runs through: the line back from a shot, counted from where it leaves the room the shot
  landed in, which is only where the NPC stood; the whole line when it never leaves that room). A pure read of the memory, the lost
  hostiles and the radio, shared by the snapshot (which words it) and, through `room_suspicion(key)`, the behaviour's entry (any entry into a suspect room is a bang one, and a late reason turns a quiet entry, E17).
- `agent_entry.gd` — doorway geometry for a tactical entry (`docs/tactical-entry.md`) and the team's claims on a doorway
  off the radio (see "Entry geometry" below).
- `agent_snapshot.gd` + `snapshot/` — the BUILD half (`domain-ai-snapshot`): turns the gathered knowledge + the tactics geometry
  into the decision SNAPSHOT (facts / sections / option groups) and owns the measured wording Von reads. Pure transform.

The controller (`ai/goal_controller.gd`) sets `agent_perception.gd`'s config fields from its exports,
calls `setup()` once to BUILD the internal modules, then `apply_config()` to configure them, and `bind(character)` once it knows the
body it drives (its first `control()`) — and
re-calls `apply_config()` each decision, so a tunable retuned at runtime reaches the modules without a
rebuild that would wipe the event memory. Nothing outside this folder holds a reference to them.

## Public interface (what the orchestrator / behaviour call)

(Config: besides the usual fields, `grenades_enabled`, `hear_grenade`, `evade_margin` and the hearing ranges `hear_walk` / `hear_run` / `hear_crouch`.)

- `setup()` (build the modules), `apply_config()` (push the config fields into them; re-callable each
  decision), `bind(character)` (the NPC's body, which every sense and query reads from then on; it tells the hostility rules the
  body's faction and hands the body on to `AgentThrow`, `AgentGrenades` and the snapshot, each with its own `bind`). No function
  below takes the character.
- `observe(rooms)` — the SEE pass, every tick: one `saw_character` sighting per visible
  character (keyed, superseded while visible; renewed every `SIGHT_EVERY_FRAMES` (3) physics frames, offset per NPC and target,
  for a character that stays in the view cone: the range/cone test runs every frame, so one that enters the cone is tested at once
  and one that leaves it is dropped at once, and what the NPC holds of a character it sees is at most 3 frames old;
  `tests/ai/perception/sight_follows_a_moving_target_test.gd`) carrying `pos`, a smoothed velocity track (`vel`, measured on `GameClock`; `track_smoothing` is the share taken per game frame, so a sighting several frames after the last takes the share they add up to),
  `facing`, the visible wound damage (`wound_dmg`, banded by the snapshot), `reloading`, `posture`, `ally`, inside/room, held item; the room the NPC stands in is
  remembered as searched (`visited_room`); an unfamiliar NPC learns rooms/objects by sight (it skips what it already knows
  before testing sight, and reads each known set once per pass). That look runs every `LEARN_EVERY_FRAMES` (6) physics frames,
  offset per NPC by instance id so a squad does not look on the same frame, and again at the start of every `sense()`, so what
  it knows at a decision is what it sees at that moment. The characters it tests are the group `characters` (interface 7)
  under the world root, itself left out, in tree order (`_other_characters`).
- **A blinded NPC** (`Character.is_blind()`, docs/grenades.md G15) sees nothing: `observe()` skips the sighting pass (no new sighting, nothing `visible`, the `_looked` state is dropped) and the learning look, so what it holds of a hostile stays where it was last seen. Contacts "age as usual" but a blind NPC cannot tell that one has gone, so `contacts()` / `lost_hostiles()` keep every sighting the memory still holds (`lead_memory_ttl`) while it is blind (`_contact_ttl`); the behaviour fires blind at the last-known spot of the engaged one. It is back to `contact_memory_ttl` the tick it sees again.
- `contacts(self_pos)` — characters seen within `contact_memory_ttl` (hostiles first, then nearest),
  with `hostile`/`reason`/`visible`/`age`. The behaviour hands the whole list to its locomotion every tick: the bodies a walk goes
  round, stops short of or gives way to are these, never one the NPC has not seen (`domain-ai-behavior`, Locomotion).
  `lost_hostiles()` — hostiles last seen longer ago, within `lead_memory_ttl` (investigation leads).
- `process_hit(data) -> bool` — a hit on/near the NPC → `under_fire` (direction + whether it
  hit), `engaged`, hostility; an ally's round (same faction) striking near it is not (it knows who fired), while one that hits it, or a
  round from a hostile or an unknown shooter (`attacker` null), is (`tests/ai/perception/ally_round_nearby_not_under_fire_test.gd`); a hit farther off within `hearing_radius` → `heard_gunfire` (a lead), but
  ONLY from a shooter not already known hostile — gunfire from a character it is fighting (or any other
  known hostile) is no mystery (COMBAT / that contact's last-seen lead already covers it), so it is not a
  lead; only an UNKNOWN shooter is. A hit on or near it from anyone but an ally also leaves `shot_from` (`{ at, pos }`: the line back
  from where the shot landed along the incoming direction to the first wall, `AgentVision.wall_hit`, at most `hearing_radius`; kept
  `lead_memory_ttl`, keyed by where the line ends), which outlives `under_fire` (`under_fire_time`) and makes the rooms the line runs
  through suspect (`docs/grenades.md` G18).
- `process_footfall(data)` — a `&"footfall"` (interface 10) heard through walls (`docs/hearing.md` H1): the step of a character
  not of the NPC's faction (the walker's `faction`, the one non-sight read of interface 7), not visible right now, within `hear_run`
  (running), `hear_crouch` (crouched) or `hear_walk` → `heard_footsteps` (`{ pos }`, keyed per walker, ttl `lead_memory_ttl`): a lead
  and a reason to suspect the room. `footfall_reach()` is the farthest any step is heard, which the controller drops the rest by before
  queuing them; a deaf NPC's footfalls are dropped by the controller (G15).
- `shots_from_room(key) -> bool` — the line back from a shot at the NPC (`shot_from`, from where it leaves the room it landed in: `AgentSuspicion.shot_line`) runs
  through room `key`: the entry guard reads it (E9: under fire, but for a walk into the room the shots came from, a walk goes through a doorway without an entry).
- `room_suspicion(key) -> Array` — the `AgentSuspicion` reasons room `key` is suspect for now (empty: none): what `entry.gd` reads to make an entry a bang one, at its start and on a late reason.
- `target_pos(target_id) -> Vector2` — hostile `target_id`'s last sighting, else (none bound) where the shots at the NPC came from
  (`shot_from`), else `Vector2.INF`: what a combat `callout` radios as `target_pos` (interface 10).
- `process_callout(data)` — an ally's radio `&"callout"` within `callout_range` →
  `heard_callout` (keyed per speaker, ttl `callout_ttl`). One carrying `cleared_room` (an ally cleared a room in a
  tactical entry) also teaches the room, marks it `visited_room` and `cleared_room`, so the team does not clear it twice.
- `process_order(data) -> bool` — an `&"order"` (interface 10, `docs/leadership.md` LD5) that names the NPC in `to` and comes from its own
  side becomes its live order (memory topic `order`, permanent, keyed `live`, replacing the one it held); a `cancel` ends the one it holds;
  true when its order changed (the controller decides at once). `order()` is the live order or {}; `end_order(id, why)` ends it (`done`,
  `refused`, `cancelled`: kept in the memory as ended, so never a ttl); `take_ended_order()` is one that ended done or refused since the last
  call, for the controller to radio (LD7). `mark_cleared(key)` ends a `stack` order whose `into` is `key` as done, the NPC's own clear or an
  ally's. A `go` (LD13) replaces nothing: when the live order is a `stack` at the go's `opening` it is kept again with `go: true` (latched,
  whenever the go came), and `process_order` returns false (no decision is forced). An `ambush` (LD15) ends `done` on first contact:
  `_end_ambush_on_contact`, run at the end of every `observe`, ends it when the NPC is `under_fire()` or sees a character it holds hostile
  (D18); footsteps heard and callouts are no contact. `quick_facts()` carries `ordered`. A callout that is only an order's progress (`order_step` with no `entry_step`) is the squad's to
  hear: `process_callout` returns before the memory, so it never replaces what that ally last said it is doing (its entry claim).
- `process_grenade(data, deaf)` — a `&"grenade"` bounce / rest: marks the grenades the NPC knows as down at that spot (seen coming down, deaf or not), and one within `hear_grenade` of a NPC that is not `deaf` is heard, so known. `process_explosion(data)` forgets the grenade that went off, keeps it as `last_burst` (`{ kind, position, frame, team }`, `frame` the `GameClock.frame()` it was noted in, `team`: the NPC or an ally threw it; a bang entry waits for its stun, and an entry goes in on its own team's burst in the room, E17) and, for a stun the NPC or an ally threw, marks the hostiles it knew
within the flash radius with a clear line from the burst as `flashed` for a few seconds (`FLASH_SHARE` 0.8 of the stun's `max_blind`, 4 s, at the burst, less with distance, at least 1 s: memory topic `flashed`), which the contact view reads as `blind` (the snapshot says "blinded by a flash"). A callout whose `status` is `grenade` / `frag_out` / `bang_out` is not an ally's plan: `process_callout` hands it to the grenade tracker (`called`) and returns before the memory (so it never counts as a held flank side or an entry claim).
- The orchestrator drops what a deaf NPC would hear (G15): its callouts, hits not on it, footfalls, grenade landings.
- `check_lead(lead_id)` — the NPC reached an investigation lead: remember it as checked
  (`checked_lead`), so it is not offered again until something newer happens there.
- `quick_facts()` — cheap facts (under fire, engaged, hostile known) between decisions.
- `sense(rooms, goal, activity) -> { facts, sections, sections_per_target, options }` — the
  BUILD pass (below). `activity` is the behaviour's current-activity line.
- Combat geometry for the behaviour: `has_line_to(target, point)`, `combat_spots(target, tgt_pos, radius, count)`,
  `note_engaged` / `engaged_fresh` / `under_fire`; `memory_size()` and
  `room_status(rooms, self_pos)` (each room tagged current / searched / unsearched / unknown) for debug.
- Entry geometry for the behaviour: `entry_geometry(opening_id, into)`, `entry_team(opening_id)` and the shared
  stack rules `entry_free_slot(team, self_id, current, mine)`, `entry_team_side(geometry, team, self_pos)` (the team's side),
  `entry_side_of(geometry, p)` (the side of the door, 1 / -1 along its wall, a point is on: the radio claims' `side`),
  `entry_stack_side(geometry, team)` (the side the NPC stacks on from where it stands: the team's, or its own when its way
  there crosses the doorway's view, E19), `entry_crossing_order(members)`, `entry_place(team, side, slot)`, `entry_side_for(geometry,
  team, slot, preferred)`, `entry_stack_point(geometry, members, slot, side)`, `entry_holds_slot(geometry, slot)`, `entry_is_tail(geometry,
  slot)`, `entry_on_stack_side(geometry, p)` and `entry_slot_reach(to, bodies)` (from where the NPC stands, `AgentEntry.slot_reach`, below) (wrappers on `AgentEntry`, which the snapshot's `entries` and `order` groups also use; the
  behaviour never reaches into `agent_entry.gd` itself; the other consumers are the human's `PlayerStack` and the `Squad` in `ai/team/`, which use `AgentEntry` directly through its published seam: `set_house`, `geometry`, `stack_side_from` and the statics `claims`, `free_slot`, `stack_side`, `side_of`, `crossing_order`, `place`, `stack_slots`, `side_for`, `stack_point`, `holds_slot`, and beside it the static `AgentGrenades.is_call(status)`, so a grenade call is never read as a stack claim) (below). `stack_room()` (the room an ordered stack holds, below). `openings` (the house's doorways, set by the controller each tick from Main's inject) and `entry_enabled`; `observe` calls `AgentEntry.warm_geometry` each SEE pass while `entry_enabled`.
- `all_seen_characters()` (every character seen, allies included), `debug_memory()` (the event log for the brain overlay and
  gcmd: `gunfire`, `footsteps` and `shot_from` among it, each `[{ pos, age }]`, `shot_from` with `at`) and `fill_goal(goal)` (the goal with `{gun}` filled in).
- `visible_points(points) -> Array` — of `points`, the subset in sight right now (view
  cone + clear line of sight, via `can_see`); the searcher's room-coverage test (behaviour samples a
  room and asks each tick which sampled points it has now seen).
- `sight_end(to) -> Vector2` — where its sight toward `to` is first blocked (`AgentVision.sight_hit`, over
  low cover), or `to`; the controller's `debug_sight_end` forwards it to the vision overlay.

## The snapshot and the wording rules — `domain-ai-snapshot`

`sense(rooms, goal, activity)` gathers the knowledge (contacts, callouts, learned rooms/objects, lost hostiles) and hands it to
`agent_snapshot.gd`'s `build(...)`, which assembles the snapshot the planner walks (facts, state sections, option groups) and owns the
measured wording Von reads. That whole sub-domain — `agent_snapshot.gd` and `snapshot/` (vocabulary + tuning, sections, option groups), the
fact / section / option reference and the Von wording rules — is the **`domain-ai-snapshot`** skill.


## Contacts and hostility

The NPC perceives characters, not "the player". The hostility rules categorize each sighting: allies
(the same faction) are never hostile; `on_sight` / `trespass` (seen inside the house)
/ `retaliate` (attacked it, via `process_hit`). A verdict is remembered as `&"hostile"` with ttl
`hostility_ttl` (≤ 0 = permanent grudge).

## Vision & knowledge

`agent_vision.gd` reuses one `PhysicsRayQueryParameters2D` for every cast, and `can_see_node` tests the cone before building
the ray's exclude list. `agent_vision.gd.can_see` is true within `view_distance`, AND within the `awareness_radius` bubble or
the forward cone (`fov_degrees`), AND with a clear SIGHT line on `QUERY_MASK = PhysicsLayers.SOLID` (walls + solid
furniture). The sight line looks OVER low cover: it walks the ray, skipping any collider whose
`coverage` (the Objects height proxy) is at or below `see_over_coverage` (default 60 — tables, beds,
islands, counters) and continuing past it, so only walls (coverage 100) and tall furniture (cabinets,
wardrobes, fridges) break the line. This is sight-only — `blocked()` / `raycast()` stay fully physical
(every solid collider counts) for line-of-fire and cover, so a bullet is still stopped by a table.
`enabled = false` = omniscient. `familiar_with_house` seeds every room/object as permanently known on
the first observe; otherwise each must be seen. People are never pre-known.

## Memory (`agent_memory.gd`)

A generic event log: `remember(topic, data, ttl, key := "")`; `is_fresh` / `recall` / `recall_all` /
`recall_aged` / `age_of` / `fresh` read back. Its only topic-aware reads are the two the whole perception asks about:
`under_fire()` / `under_fire_from()` (the direction the last fire came from) and `engaged()`; the snapshot reads them there and the
face forwards them (`under_fire()`, `engaged_fresh()`). A write with a `key` (the event's subject) SUPERSEDES the
live event with the same topic + key — something re-observed every tick stays one entry instead of
flooding the log and volume-evicting every other expirable event. Cleanup on every write: age-expired
first, then, while over `capacity`, the oldest expirable. Permanent events (ttl ≤ 0) never age out
and are never volume-evicted. Events are stored as one list per topic, each in write order, every event carrying its write order across topics (`seq`): a keyed write
supersedes in place within its own topic's list and every reader walks only the topic it names, so the cost of a call follows the number
of events of that topic, not of everything remembered (a familiar NPC holds a permanent `saw_room` / `saw_object` per room and
furniture piece). `seq` keeps the promised order: newest first for readers and `fresh()`, oldest expirable first for volume eviction.
`_prune` skips its scan until the earliest deadline among the stored events (`_earliest_expiry`), and every reader takes the clock
once. **The clock is `GameClock`** (General, interface 11; `docs/leadership.md` LD1): an event's `at` is `GameClock.msec()`, game time that
stands still while the tree is paused, so a pause of any length expires nothing, and a headless `--fixed-fps` run ages events at the
sim's pace (a contact's 4 s are 4 s of sim). The rest of the perception's ages read it too: the sightings' velocity track, `last_burst`'s
`frame`, the grenade replan, `routes_ready`'s `WARM_CAP_MS` and `debug_memory`'s `left`. `tests/ai/perception/memory_matches_reference_test.gd` runs random writes through the memory and a plain ordered log and compares every reader. Topics: `saw_character` / `saw_room` / `saw_object` / `visited_room` /
`cleared_room` / `hostile` / `under_fire` / `shot_from` / `engaged` / `heard_gunfire` / `heard_footsteps` / `heard_callout` / `checked_lead` / `flashed` / `order`.

## Tactics (`agent_tactics.gd`)

The flank behaviour these queries should deliver, and the tests that assert it, are in
`docs/flanking-behavior.md`.

Whether the NPC is hidden from a hostile where it stands is worked out once per snapshot (`ctx.covered_from`), not per candidate
spot. Pure queries over known contacts, the physics space (via the vision rays) and the nav map
(`NavBuilder.snap` / `route` / `path_length`, interface 9). A target's flanks are measured in its own frame (its
last-seen facing, else the side facing this NPC): left / right / rear candidates at `flank_distance`,
sampled across `flank_arc`, snapped to the navmesh, preferring a clear shot. Each spot is annotated
with clear shot, cover within a step (`cover_min`), route length + exposure (share of route samples
the target can see; for a flank, only samples inside the target's view cone, `watch_arc` around its
front, so a route behind its back is hidden — `route_exposed`'s optional `front`), `crosses` (a known
hostile the route passes), `held_by` (ally within `flank_ally_radius` on that side, or a callout point
there), `exposed_to` (other hostiles), `heading_toward` and `ally_lane` (a seen ally whose line of fire
on the target passes within 40 px of the spot, or that the route there crosses). Hostile fronts
(`ctx.fronts`, built once per `sense()`) serve both the flank frames and the watch test below. The
snapshot turns these into boolean tags on each `flank_sides` option — `held`, `crosses`, `no_shot` (no
clear shot), `heading`, `lane` — which the `flank` node's `drop_tags` drop; the side stays in
`debug_zones()` with its words ("line blocked from there", "they are moving toward that side", "in X's
line of fire").

Route safety: `route_crosses(path, hostiles)` names a hostile whose last-known position lies within
`route_clearance` of the route AND nearer than the route's start (walking away from someone close by
is not passing them). `watched_in_open(ctx, p, path)` names a hostile that would catch the NPC in the
open: looking toward `p` (within `watch_arc` of its front; an unknown facing counts as facing the NPC)
with a clear line and no cover within a step of `p`, or — while the NPC is now hidden or covered from it
— looking along a mostly exposed route there.

Fire spots are sampled on rings around the NPC (`combat_ring_radius`, ×2) and around the target (each of
`fire_spot_distances`); a spot needs a clear shot in range and must pass both route-safety tests, and
the best per 8-way sector around the target is kept (cover close by, then the shortest step). `here`
is never screened; the ambush spot passes the same tests. Advance spots lie along the route; retreat
spots (`retreat_positions`) come from known rooms, the cover spots on the ring round the NPC (`combat_ring_radius` x2) and a spot
beside each ally (`_beside`: `BESIDE_ALLY` 44 px behind it from the nearest threat, else to one side, on open floor with no wall
between), each snapped onto the navmesh and judged where the walk there ends. One is kept when it takes the NPC out of sight of every
threat while it stands in sight of one, else when it lies at least a `STRIDE` farther from the nearest threat (rays toward a threat
exclude hostile bodies); never one a known character stands on (`TAKEN` 32 px) nor one where the NPC already stands (`STRIDE` 32 px of
walking). `where_it_stands(ctx, p)` (the walk to `p`'s navmesh point is under a `STRIDE`) is the same test for the snapshot's LOCATE
and its "where the shots came from" lead (other leads lie at fixed points and reaching one spends it). Why (issue #51 R12,
`docs/tactical-entry.md` E9): a move that ends the tick it begins is offered and taken again every other frame. Tests: `ai/combat/retreat_never_where_it_stands`, `locate_never_where_it_stands`, `retreat_out_of_sight_goes_farther`.
A character is never cover; a blocking object is
named by its `object_name`, a character by its name, anything else as "wall".
`combat_spots` (ring around the NPC: fire vs cover) also serves the behaviour's peek-and-cover.

**Throw spots** (`throw_spot(ctx, spot, reach, lob, ex, keep_out)`, issue #51 R13 / R15, `docs/grenades.md` G17): where to throw onto `spot` from when the lob
from where the NPC stands fails (out of range or not clear). Candidates on rings round the NPC (`THROW_RINGS` 48 to 240 px, `THROW_DIRECTIONS` 16, none past
`throw_spot_walk`) and round the spot (`THROW_REACH_SHARES` 0.95 / 0.8 of `reach`), cheap tests first (straight distance under `throw_spot_walk`, snapped onto the
navmesh within `SNAP_TOLERANCE`, within `reach` of the spot, more than a `STRIDE` away, not inside `keep_out` (the room the hostile holds, or the shots' room),
the `lob` callable: `AgentThrow.throw_clear` from there), then sorted as the fire spots are: hidden from the spot (`blocked`: low furniture between), then with
cover close by against it (`cover_near`: a jamb, a piece), then the straight distance; routes only for the first `THROW_ROUTES` (10), through the optional `route`
callable (`{ path, len, detour }`: the snapshot's `_throw_walk`, the walked route of `AgentEntry.walk_route` and whether the entry guard would stop it), kept when
the route reaches it, is at most `throw_spot_walk` (250 px, the controller export in the Grenades group) and passes no known hostile (`route_crosses`); the pick is
the first with no `detour`, then hidden, then covered, then the shortest walk. `{ point, route_len, hidden, cover, detour }` or {}. Cost: ~150 snaps and lob tests and up to 10 routes, only for a throw the NPC cannot make where it stands.

## Entry geometry (`agent_entry.gd`)

The behaviour asked of it is `docs/tactical-entry.md`. Given the house's openings (Main's `WorldGen.get_openings`, handed
in by `set_house` on each observe) and rooms, `entries_from(room_key)` lists the doorways out of the NPC's area (outer
doors from outside, a room's doors into the next room), `watch_doors(room_key, exclude_id, is_cleared)` those of a cleared
room on into rooms not cleared (what the team covers after clearing it, E8; the perception's `entry_watch_doors(into, opening_id)`) and `geometry(id, into, map, space)` lays one out, built once on a
baked nav map and cached (walls do not move): `out` (unit normal away from the room, from the room edge the door lies on)
and `along` (the wall's axis), `wall` (wall length either side), `side` (the side with more wall, 0 when even; once the slots are laid, the side whose file holds more against the wall when they differ), `slots`
(single file against the wall on each side: `wall_standoff` off it, the first a body clear of the jamb, then every
`stack_spacing` (44 px: clear of the neighbour's footprint, outside the 34 px hole a body at rest on the next slot cuts in the
steering map, so a slot is never a destination inside a teammate), snapped), `pie` (`pie_steps` points `pie_radius` from the threshold, from 55° to 25° off the axis), `lookouts` (the slots and pie points as laid out, before they are snapped
onto the navmesh: where an entry's stack and point stand, or near it; what an ambush post is hidden from), and the
`capacity` (how many go in: 2 when a side of the room is under `short_room`, the controller's `entry_short_room`, else `MAX_SLOTS`: E13), the
room's four corners inset `corner_inset`, each `near` (on the door's wall), `side` and `hard` (no sight line from 24 px
outside the threshold). The statics `claims(id, callouts)` (allies' live entry claims: slot, side, step, covering, `pos`, `bang`, `bang_off`, `stuns`, `frags`, `claim_frame`, `claim_pos`, `move_up`, `pie`, `human`, `leader` and the order fields below; `abort` and `done` drop one), `free_slot(team,
self_id, current, mine)` (the lowest free slot; `mine` = `{ frame, pos, g, side, move_up }`: two claims on one slot made on the same frame and
side settle by distance to the slot's point, laid among the rest (`_wins`; within 0.5 px, or otherwise, the lower instance id), and a slot
claimed on this NPC's frame by someone farther is taken from them, so the settling runs down the stack; a claim that moved up into a slot
(`move_up`) holds it against one that did not, and the NPC it moved up past takes the freed slot) and `stack_side(g, team, self_pos)` are shared with the snapshot's `entries` group and, through the `AgentPerception` wrappers, with the behaviour's `entry.gd` (`domain-ai-entry`). `stack_side` is the
point's side (its slot 1 claim), else `g["side"]` (the side whose wall holds more of the file against it, once laid; before, the side with more wall), else the member's own. **A split stack (E19):** `stack_side_from(g, team, from, map, space)` is that side
unless `cuts_view(g, from, to, map, space)` (the plain route from `from`, starting outside the doorway's `door_view`, crosses the door's axis inside the view: a walk
that starts in the view or goes round it does not) says the way there crosses the view; then the member's own side (`side_of`). The slots are numbered across both
sides in claim order; `place(team, side, slot)` is a member's place in its side's file (its slot less the claims ahead on the other side; the slot itself on a one-sided
stack), and `stack_point` (below) is where that place stands. `crossing_order(members)` is the order a stack crosses in: by slot, or on a split stack the point, the other side's front man,
then the sides in turn. An `AgentEntry` built outside the perception (`PlayerStack`'s, the `Squad`'s) makes its own `AgentVision` for the view rays. Tunables: the controller's `entry_*` exports.

**Where a stack stands (E20 to E22, `_lay_slots`).** On a baked map with a physics space `_build` also lays the slots: `from` / `from_room` (the
room the stack stands in, "" / a zero rect outside), `kind` and its layout, `wall_n` (how many slots the wall, or the fewest-seen spots,
hold), and past them `seq` (the overflow: open floor, then the tail from `tail_from`) and `capped`; `spacing`. `kind`: `wall` (a spot against
the wall beside the door out of every other doorway's view, `_has_wall_spot`): `files { 1: [{ point, row }], -1: [...] }` packed exactly at
`stack_spacing` from the wall band (`_band`: `SLOT_BODY` past the jamb to the stack room's corner, outdoors `OUTDOOR_REACH` 320 px, or
another doorway's funnel; `SLOT_OUT_MIN`–`SLOT_OUT_MAX` 14–110 px out; `WALL_GRID` 8 px, on `SLOT_STEP` 4 px when short of a full stack;
`_pack` / `_most_spaced` within `PACK_BUDGET` steps), `row1` (how many of each against the wall, within `ROW1_DEPTH` 50 px) and `g["side"]`
from those counts; `views` (every wall spot is in another doorway's view): `views_lays`, each stack size on each first side from the points
seen by the fewest doorways; `open_floor` / `dead_end` (no wall spot; `dead_end` when the stack room has no other doorway). A point is kept
only on the navmesh within `SLOT_SNAP`, inside the stack room by `SLOT_ROOM_INSET`, on the stack side, reached from `SLOT_REACH_OUT` out
without going through the doorway, out of other doorways' funnels (`FUNNEL_DEPTH`) and, but for `views`, their views (`VIEW_MARGIN`); a
navmesh carved round solid furniture skips it (E22). `_overflow`: `_open_floor` (`OPEN_GRID` 8 / `OPEN_GRID_FINE` 4 px; outdoors within
`OUTDOOR_FLOOR` 300 px; past a short wall or a `views` way in, `strict`: off the wall band and out of other doorways' views; exact when
capped), then `_tail_spots` (in the room beyond the stack room's nearest other doorway, within `TAIL_REACH` 140 px of it); `capped` (a dead
end, or outdoors past a short wall) takes no tail. The statics every stack reads: `stack_slots(g, count, side) -> [{ n, point, side, row }]`
(only as many as `holds_slot`), `side_for(g, team, slot, preferred)` (E21: its side while that side's row 1 has room, else the other's, then
a second file on its side, then the other's; past `wall_n` or with no files, the side the slot lies on), `stack_point(g, members, slot, side)`
(INF for a slot a dead end does not hold), `holds_slot(g, slot)`, `is_tail(g, slot)`; and the method `on_stack_side(g, p)`.
**Shared, and laid ahead.** `geometry` keeps each doorway's layout in the instance's `_cache` and in the static `_shared` (navigation map RID
-> `"<_tuning()>|<id>><into>"` -> geometry, `_tuning()` being `_tuning_inputs()` (the house and the tunables `_build` reads) as a string), dropped
when the map's planning region leaves the tree; only a layout snapped on a baked map is kept. `warm_geometry(map, space)` lays at most one
missing way in per physics frame among every NPC (`_warmed_frame`), so a house's doorways are laid in the frames after the bake, not in a
decision. Once a pass finds every way in laid it remembers that shared dictionary and the `_tuning_inputs()` array (`_warm_done_in`,
`_warm_done_for`) and returns at once until either changes: comparing the array costs about 0.2 us against about 3 us to format the key, and
scanning every opening x room per NPC per tick cost 0.1 to 0.2 ms a frame in the match guards. Laying one way in costs 7 to 52 ms
(garage_home's ten: `_band` 2 to 15 ms, `_overflow` 10 to 28 ms); all ten are laid by 0.22 s into a match, before the perf guards measure
(`docs/leadership.md`, Performance).

**Cleared rooms and the entry guard (E9).** `cleared_room` (keyed per room, ttl `search_memory_ttl`) is not `visited_room`:
standing in a room visits it, but a room is *cleared* only by `mark_cleared(key)`: the behaviour calls it when an entry
finishes (`entry.gd` `_finish`, own clear or an ally's; `domain-ai-entry`) and when a search covers its room by sight, and `process_callout`
when an ally radios `cleared_room`. `is_cleared(key)` reads it; the snapshot's `entries` group skips only cleared rooms
(search ranking still uses `visited_room`). `threshold_ahead(path, from_idx, max_dist)` (a thin wrapper on
`AgentEntry.threshold_ahead`) walks a nav path and returns the first doorway whose wall plane a step crosses, within the
doorway's width and heading into a room that is not the one the NPC is in and is not cleared: `{ opening, into, dist }`, or
{}. The last step is extended by `THRESHOLD_EXTEND` (30 px) so a destination that is the doorway counts. The behaviour's
entry guard calls it every tick. `passing_ahead(path, from_idx, max_dist)` (over `AgentEntry.passing_ahead`) is its sibling for E15 / E18:
the first doorway **view** the walk comes into from outside it (any doorway into a room not clear for passing: inside the house or out, exterior doors too, however far out from the wall; not the NPC's own room, nor a doorway of a room the walk goes into by any of its doors, which the entry into that room covers): `{ opening, into, dist }` (`dist` = px of walking until it is in the view), or {}.
**Doorway views and the walked route (E18, `agent_entry.gd`).** `door_view(id, into, map, space)` is the view out of a doorway (the area outside it
seen from inside room `into` through it): a polygon from the rays from the room's two far corners through the opposite jambs, `door_view_depth` (450 px) long,
each ray a fan cast from three points in the gap (the middle and each jamb, `VIEW_APEX_OUT` 8 px off the wall plane) and stopped at the first wall
(`AgentVision.wall_hit`: static bodies only, furniture and characters are looked through), the three fans fused, and for a doorway between two rooms cut at
the edge of the room in front of it (so a view does not run on through the next doorway into another room). Laid out once per doorway on a baked map and kept. `avoided(here_key, map, space, exempt)` is the set of views a walk from room `here_key` keeps out of: those of every doorway into a room that is not
clear for passing (`AgentPerception.is_pass_clear(key)`: the `cleared_room` memory's age is within `entry_pass_clear_time`, 60 s; `is_cleared` stays the
entry's), other than the NPC's own room; with `entering` (`"<opening>><into>"`, the entry a walk is the approach of) that doorway's own view
always counts, from inside the room too and cleared or not; `{ key, holes, views }` (each view `{ id, into, poly, joins }`, `joins` the rooms the doorway joins), worked out once a physics frame.
`walk_route(from, to, map, space, entering)` (over `AgentPerception.walk_route(to, entering, from)`) is the route the NPC walks: the plain one, unless it comes
into one of those views (or, with `entering`, goes into the room being entered) and the route on `NavBuilder.avoid_map` for the set (less
the views `from` stands in, `_left_from`; when that route goes into the room being entered, the route on the map with the room's floor carved too, `_with_room`, so the room-carved map is asked for, baked and kept only while an approach needs it) reaches `to` (within `AVOID_REACH` 24 px) no longer than `door_avoid_ratio`
(2.0) x the plain length + `door_avoid_slack` (300 px); failing that, with `entering`, the route round that doorway's own view and the room
at least (`_entering_set`), capped the same unless `ordered_approach` (set by `_sync_walks` from `ordered_walk`: uncapped, D4):
`{ map, path, len, plain_len, doors, pending, views }` (`len` the whole walk, the steps onto the route and from its end to `to` included;
`pending`: the plain route crosses a view and the avoid map is still baking). `warm(from, map, space)` (over `AgentPerception.routes_ready()`) asks for the avoid map of the room the NPC is in and
says whether it answers; the controller starts no decision before it does (at most `WARM_CAP_MS` 3 s of game time), so the route bands a snapshot reads are the walked ones.
`slot_reach(from, to, map, bodies)` (over `AgentPerception.entry_slot_reach(to, bodies)`) is whether any way at all reaches `to` with a body standing at each
point of `bodies` at body width (a `BODY_SEGMENTS`-gon of `SLOT_BODY` + `NavBuilder.OBSTACLE_MARGIN` each, the steering map's carve of a body at rest, on an
`NavBuilder.avoid_map` of their own keyed by the bodies on a 4 px grid): 1 when its route ends within `AVOID_REACH` of `to`, or within
`SLOT_LAST_LEG` (64 px) of it with the plain way on from there that long at most and passing none of `bodies` closer than `SLOT_PASS` (32 px:
Locomotion's last leg, the way into a slot between two taken ones, which lies inside their carved margins); 0 when not, -1 while that map
bakes (asking starts it), 1 with no planning region or the plan map not baked yet (no verdict: not sealed). It is what the entry asks before it reads a hold as sealing its slot (E2, `domain-ai-entry`).
Config on the perception (from the controller's exports): `door_view_depth`, `door_avoid_ratio`, `door_avoid_slack`, `entry_pass_clear_time`; views are
avoided only where `entry_enabled` and `entry_guard` are.
**Defend spots (`docs/leadership.md` LD8, D2).** `defend_spot(room_key, nth, count, map, space)` is where member `nth` of `count` ordered to
defend a room holds it: the room's doorways sorted by id, member `nth` taking doorway `nth` mod their number (the extras doubling up on its
other side), the spot `DEFEND_DEPTHS` back from its wall and `DEFEND_LATERALS` past its jamb (best 100 / 50 px), inside the room by
`DEFEND_INSET`, snapped onto the navmesh, scored out of every doorway's fatal funnel first (within `DEFEND_BODY` of its width, nearer its wall
than `DEFEND_FUNNEL_DEPTH`), then with a sight line to its doorway, low furniture on that line (cover seen over), its side and the distance
from the best; a lone member of a room with several doorways takes the spot that sees the most. `{ spot, door, door_pos, doors }` (`door` ""
and `door_pos` INF for that lone member, who turns among them). The snapshot's `order` group calls it. `static normal_into(rect, pos)` (the
unit normal into a room from the edge a doorway lies on) is also read by the squad (`ai/team/squad.gd`).
**Ambush posts (`docs/leadership.md` LD15, D17).** `ambush_spot(id, room_key, nth, count, map, space)` is where member `nth` of `count` ordered
to ambush doorway `id` from room `room_key` waits: `{ spot, door_pos, seen }` (`door_pos` the doorway's centre, where its gun goes; `seen` how
many lookouts see the post, 0 hidden), {} for a doorway or room it does not know or no post. The candidates (`_ambush_posts`, kept per
doorway and room side in `_posts` once worked out on a baked map, cleared by `set_house`) lie `AMBUSH_DEPTHS` (40 to 160 px) back from the
wall and `AMBUSH_LATERALS` (30 to 260 px) past the jamb, either side, inside the room by `AMBUSH_INSET` (22 px), through `_defend_candidate`
(snapped, its funnel, its sight line and cover on the line to each doorway); one off the doorway's sight line or on its axis (within half the
width + `DEFEND_BODY`) is dropped. Each is scored `seen` x 1000 + funnel x 500 + (no cover on its line to the threshold) 300 + |depth -
`AMBUSH_DEPTH` 110|, `seen` counting the geometry's `lookouts`, slots and pie points that see it (`_sees_from`: `AgentVision.sight_hit`, over
low cover, at any range and facing); a post seen by none is hidden only if it is hidden from the 8 points `AMBUSH_SLACK` (12 px) round it too.
Members alternate sides of the axis, the side with more wall first, and two posts stand `AMBUSH_SPACING` (44 px) apart. The snapshot's `order`
group calls it.
**An ordered stack's walk (`docs/leadership.md` LD9, D4, D11).** `ordered_walk` (set each tick by the behaviour while it walks an ordered stack's
way to its door) makes `_sync_walks` turn the view avoidance on (`AgentEntry.avoid_views` = `entry_guard` and (`entry_enabled` or `ordered_walk`))
and, for an NPC with `entry_enabled` off (a defender), swap `AgentEntry.pass_clear` for `_passable` and have `threshold_ahead` pass rooms
`seen_empty(key)` says it stood in within `entry_pass_clear_time` with no hostile sighting in them (the latest of each hostile it knows, within that
time); `avoided` keys its per-frame cache on the `pass_clear` rule too. On an ordered walk the room its stack holds is clear too: `stack_room()`
(once a physics frame: the live order is a stack, `ordered_walk`, and a claim on its doorway under the same `order_id` is at `ready` / `bang`
→ the geometry's `from`; else "") counts as cleared for `threshold_ahead` and as pass-clear (`_pass_clear_ordered`, handed as `pass_clear` to
an ordered walk with entry on; `_passable` adds `seen_empty`), D20. An invader's walks are otherwise unchanged. The team's claims (`AgentEntry.claims`)
carry an ordered member's `order_id`, `order_bang`, `order_mode` (LD14; read from `order_bang` for a claim without one), `order_hold` and
`order_go` (LD13) and `order_side` ("" / false / quiet / false / false / 0 for others), which `entry.gd` reads.
`room_doorways(room_key)` (over `AgentEntry.room_doorways`) lists every doorway of a room, outer doors
included, as `{ id, pos, width }`: the places a resting NPC watches (`Watch.idle_gaze`, `domain-ai-watch`).


## Grenades (`agent_grenades.gd`, `agent_throw.gd`; spec `docs/grenades.md` G15, G16)

**What it knows (`agent_grenades.gd`, `known_grenades()`).** A live grenade is a node of the group `live_grenades` (Items: `kind`, `fuse_left()`,
`throw_stats()`, `thrower`). The NPC knows one by **sight** (`observe`, every tick, only while the group is non-empty: in the view cone with a clear sight line;
its `point` follows the grenade), by **hearing** it come down (`hear`: a `&"grenade"` bounce / rest within `hear_grenade` 300 px, not deaf; the point is where it
landed), by an ally's **callout** (`called`: the `point` the call names, within 150 px of a live grenade of that kind) or because it threw it (**own**: `thrower` is
the NPC; always known, blind or not). A grenade keeps the source it was first known by (a later sighting, landing or call only keeps its spot true). Each is `{ point, kind, fuse_left, fuse, radius,
source }` (`radius` = `AgentThrow.radius_of(kind)`, off the `throw_stats()` just learned from that grenade); it is forgotten at the burst (`&"explosion"`, or the node leaving the group). A bounce / rest event marks a known grenade `landed` (and `rested`) at that spot.

**The danger zone and the safe spot (`agent_throw.gd`).** The cover rule is the blast's own (G7), asked of the Projectile System so the AI keeps no copy (`shielded` calls `Explosion.shields`, interface 3): from the burst a wall always stops the line, furniture
stops it when its `coverage` is above the body's height (the standing and crouched heights the character reports, `Character.posture_coverage`, read each `observe` by `learn_body` into `stand_height()` / `crouch_height()`; 60 and 35, `docs/cover-and-stance.md`), characters stop
nothing. `in_zone(space, kind, radius, burst, p, height, exclude)`: within `zone_radius` (a frag's blast radius + `evade_margin`, a stun's flash radius) and not shielded.
`escape(...)` returns `{ spot, crouch, route }`: candidates are the circle just outside the zone (`zone + OUTSIDE_SLACK` 30 px), the shadows behind what the rays from the burst
meet (the first stopper for a crouched and for a standing body, `Explosion.first_stop`, 32 and 72 px behind it) and rings round the NPC; each is snapped onto the navmesh (`NavBuilder.snap`, dropped
if pulled more than 40 px), judged (outside the zone, or shielded standing = out of line, or shielded only crouched = `crouch`), **every** survivor is routed
(many candidates are the same point, the standing and crouching probes meeting the same wall: each point is snapped, each spot judged and each
route measured once, `tests/ai/grenade/escape_spot_matches_plain_test.gd` pinning the answer to the plain loop)
(`NavBuilder.route`; a straight line says nothing, a spot just behind a wall can be a house away) and the shortest route within `(fuse_left - 0.4 s) x run speed`
(`RUN_RELIABILITY` 0.85 of `Character.run_speed()`, or `Character.walk_speed()` once stamina is below `RUN_STAMINA`: both slowed by a
stun or a heavy outfit; `tests/ai/grenade/throw_timing_counts_slowed_walk_test.gd`) wins; `spot` is `Vector2.INF` when none is in time. Cost: ~150 snaps, ~300 rays and ~100 routes, only when a plan is
made; in the grenade match guard a plan made alone costs about 2.5 ms of burst work (the candidates round the burst, their snaps, the verdicts) and 1.2 ms of routes.
`can_lob(space, at, to, max_range, exclude)` is the throw test of the GRENADE tactic, the shots' group, the throw's re-check and the bang (within range, and `throw_clear`: the lob from
where the grenade leaves the thrower's hand, `release_point` (the thrower's hand as it faces the spot, `Character.throw_release_offset`: the `throw` stance's hand, 6 px behind and 15 px right of it, learned with the grenades carried in `learn_carried` (the centre until one is), held
off a wall like the character's own hand), and the band `LOB_MARGIN` 8 px either side of that line the whole way (parallel edges, not converging on the spot: a jamb far along is met with the grenade's full width), each with nothing taller than `LOB_CLEARANCE` 50 px, the release height, on the line: a centre line
that grazes a jamb is a grenade that strikes it). `reach_of(kind)` is the range less `REACH_SLACK` 15 px: how far from its spot a thrower lets go, and the reach a throw spot is chosen in.
`throw_clear_on_arrival(space, at, to, exclude)` is `throw_clear` from `at` and from `ARRIVAL_SLACK` (6 px, the walk's own arrival) off it in the four axis directions: the test for a
spot the thrower walks to (a throw spot's `lob` callable; the bang's spot, through `AgentPerception.can_lob(..., walked = true)`).

**Shared on a physics frame (`_shared_burst`, `_shared_snaps`).** What depends on the burst alone is the same for every NPC fleeing it, and an evade
wave is 4 to 8 NPCs planning on one frame: `escape` keeps the candidates round the burst (`_around`: the circle and the shadows, ~50 rays), each spot's
verdict (keyed `[space, burst, kind, out_r, cover_reach, stand height, crouch height, the excluded rids' ids sorted]`, so a grenade that moved or an NPC
with other heights or margin has its own entry) and each candidate's navmesh spot (per map) in static dictionaries for the physics frame
(`Engine.get_physics_frames()`, cleared when a new one begins). Inside a physics frame the space and the map hold still for these queries (furniture
moves in the step, a dented collider is rebuilt deferred, the map syncs after the frame's callbacks, the characters are excluded), so what is shared is
what each NPC would work out; outside one (`Engine.is_in_physics_frame()` false) nothing is kept. Only `[from]`, the ring round it (`_ring`) and the
routes are the NPC's own. `_candidates` (`[from] + _around + _ring`) stays the plain list the tests compare against. On the grenade match's evade waves
the worst wave measured (8 NPCs planning on one frame) went from 35.9 ms of planning to 17.4 ms (`docs/leadership.md`, Performance). Tests:
`tests/ai/grenade/escape_spot_matches_plain_test.gd` (120 escapes on one frame, many bursts) and
`tests/ai/grenade/evade_wave_spots_match_own_plan_test.gd` (five defenders plan together; each plan's spot equals the plain search's for that NPC on
that frame).

**Cover from a flash.** For a stun (`AgentThrow.cover_reach(kind)`, the `flash_cover_reach` of the stun's stats, 30 px, learned off the grenade: below) a piece of furniture shields a body from the burst only when the body is within that many px of it
(`shielded`'s `reach`, handed to `Explosion.shields` as its `cover_reach`); a wall always does; a frag's blast keeps the plain rule. `escape` also tries a spot right against the far face of each stopper near the burst (`FAR_PROBE`, `FAR_STEP`).

**Its own grenade (`_note_own`).** A grenade the NPC threw is known at once, and until a bounce marks it landed its spot is where it was aimed (`Character.aim_target()` from the hand, no further than that kind's throw range, `AgentThrow.range_of`), not the hand
it just left, so the zone it is in is the one the burst will have. **Replanning** is counted in `GameClock` frames (`REPLAN_EVERY` s of game time), not wall-clock ms: a fast headless run outruns the wall clock, and it runs on through a pause.
`AgentThrow.escape` takes the NPC's own position as the first candidate (already behind cover that shields a crouched body, it need not move).

**What it knows of a grenade it carries (`AgentThrow`).** No copy of the tuning: `learn(stats)` takes in what a grenade tells (`{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`, interface 6/7) from `Character.throw_stats(slot)` of every grenade the NPC carries (`learn_carried()`, every `observe`) and from each live grenade it notes (`ThrownGrenade.throw_stats()`, in `agent_grenades.gd`), and keeps it by kind, so it outlives the last grenade thrown. `range_of(kind)`, `radius_of(kind)`, `fuse_of(kind)`, `max_blind_of(kind)` and `cover_reach(kind)` answer from it (0 / 0 / 0 / 0 / INF for a kind never met; the flash a hostile is taken to be blind for is `FLASH_SHARE` 0.8 of `max_blind_of(&"stun")`); `AgentPerception.can_lob(at, to, kind)` (range and `throw_clear`), `throw_clear(at, to)` (the lob alone, from the hand), `grenade_reach(kind)` and `grenade_fuse(kind)` wrap them for the behaviour sub-domain; the static `carried(character)` (the kinds with a count, a frag
first, via `Character.item_count(ItemRegistry.FRAG_SLOT / STUN_SLOT)`) and the geometry the snapshot's `grenade_group` uses (`can_lob`, `in_zone`, `escape`, `run_speed`).

**The plan (`evade_plan()`).** For the known grenade that goes off first among those the NPC is in the zone of (or is already running from): `{ id, point, kind, radius, spot,
crouch, fuse_left, landed, lies }` (`landed` whether it has come down, `lies` where it is known to be now; `point` is where it was when the plan was made: a frag entry's stack
reads both, `Entry.expects_burst`, `docs/leadership.md` LD14). Made when the NPC is first inside a zone, made again when the grenade has moved 48 px (in flight, a bounce), or any distance that leaves the spot in its line
(`_still_safe`: a grenade rolling on a few px by a doorway; test `ai/grenade/evade_replans_when_spot_in_line`), at most every 0.15 s, and kept while the
grenade lives, so the NPC holds the spot until the burst. A grenade in flight is reacted to from where it is; the callout waits until it has come down (`announcements()`, the
spot it LANDED, which the allies' plans need) and is repeated once if it rests 30 px or more from there; an ally's call or the NPC's own throw is not radioed again.
The behaviour carries the plan out (`domain-ai-behavior`, "The evade reflex").

**Wrappers for the behaviour sub-domain on `AgentPerception`:** `can_lob(at, to, kind, walked := false)`, `throw_clear(at, to)`,
`grenade_reach(kind)` and `grenade_fuse(kind)` (above), `in_grenade_zone(kind, burst, p)` (a standing body at `p` inside the zone of a `kind` bursting at `burst`,
`AgentThrow.in_zone`, every character's body excluded: the frag entry's slot check, `docs/leadership.md` D16), and `evade_plan()`, `known_grenades()`,
`grenade_announcements()`. Tests: `tests/ai/grenade/`.
