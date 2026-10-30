---
name: domain-ai-perception
description: Deep implementation detail for the AI PERCEPTION sub-domain (scenes/ai/perception/) — what an NPC knows and how it is worded for Von. The sight sense, hostility rules, the confinement (where it may act: territory, ordered room, squad leash), the generic event memory (with keyed supersede), movement tracks/facing/visible wounds, gunfire and footsteps heard, where shots came from, allies' radio callouts, the live grenades known (seen, heard, called, own) and the plan to get clear of them, a blinded or deafened NPC, leads, searched rooms, the tactics geometry (flank sides, fire/advance/retreat spots, route length + exposure, cover), the doorway geometry for tactical entry (agent_entry.gd: stack slots, pie arc, hard/soft corners, the team's slot claims, defend and ambush posts, where an entry's grenade lands), the doorway views and the walk that keeps out of them (agent_door_views.gd) and its hand-off to the decision SNAPSHOT (the snapshot itself, its wording rules and option groups are the sub-domain `domain-ai-snapshot`). Use when editing scenes/ai/perception/ (except the snapshot) or working on vision, memory/eviction, hostility, flanking geometry, entry geometry, callouts, or combat line-of-sight. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Perception sub-domain (`scenes/ai/perception/`)

The SENSE half of the NPC brain: it turns the world into what the NPC *knows*, and turns that into the
snapshot the decision planner walks. It holds no policy — it never decides, picks or gates by goal. It
owns nine internal modules and presents one public face, `agent_perception.gd` (a `Node`).

Files:
- `agent_perception.gd` — the public face: the lifecycle (`setup`, `apply_config`, `bind`), SEE (`observe`, through its
  `sight` and `house` parts), the reads the controller and combat make every tick, and the BUILD entry (`sense`) that gathers knowledge and
  delegates to the snapshot author; the contacts view and the event intake are its parts' (below).
- `perception_sight.gd`, `perception_house.gd`, `perception_hearing.gd`, `perception_orders.gd`, `perception_contacts.gd`,
  `perception_grenades.gd`, `perception_entry.gd`, `perception_views.gd` — the face's parts, held as `sight` (the sight sense
  `vision`, what is in view `visible_now`, the tracks, `blind` and the sight cadence), `house` (the rooms, `openings` and
  `entry_point`, what it has learned of the house and learning by sight, the interactables, its `post`),
  `hearing` (hits, gunfire, footsteps and callouts heard, with the suspicion module), `orders` (the live order), `contacts` (the
  characters known, with the hostility rules), `grenades` (the grenade geometry `throw` and the live grenades `live`, what it
  carries, the latest burst), `entry` (the doorway geometry `doorways` and the claims heard `ledger`, the rooms cleared) and `views`
  (the doorway views `views` and the walk rules, `ordered`): preload consts with no `class_name`, built once in `setup()`, each holding the perception (a node).
  `views` is the one part another sub-domain holds: behaviour's locomotion (`behavior/locomotion/loco_doors.gd` preloads `perception_views.gd` to type its
  `doors.views`, handed `perception.views` by `Behavior.setup`) asks it `walk_route`, the seam the architecture's AI row names beside `entry.stack`.
- `perception_confinement.gd` — the face's part `confinement`: **where the NPC may act** (`GLOSSARY.md` Confinement). A data leaf (preload
  const, no `class_name`, built once in `setup()`, holding no owner: `tests/ai/ai_parts_free_suite.gd`), unlike the other parts. It holds three
  rules, all of which must hold at a point, and the house `rooms` it judges by (set to the face's rooms each `observe`):
  - `inside_only`, the territory (a defender keeps inside the house, from `tuning.decision.defend_territory`);
  - `room`, the room a `defend_room` order keeps it to ("" with none, `docs/leadership.md` LD8);
  - `leash_center` / `leash`, the squad leash (its leader's live position while it follows and holds no order, `Vector2.INF` otherwise;
    `SquadFollowConfig.leash` px, 0 with none, LD23).

  `refresh(territorial, order, center, radius)` takes the tick's rules (only a `defend_room` order names a room); the controller's reflexes
  call it once a tick in SENSE after the whole order intake (`npc_reflexes.gd` `refresh_confinement`, from `follow_squad`), and again as
  `_start_decision` refuses an order. `allows(p)` is true when the territory is off or `p` is in a house room, no room is ordered or `p` is
  in it, and no leash is set or `p` is within `leash` of `leash_center`. `allows_option(o)` judges a decision option where it acts:
  `params.from` (the spot a grenade is thrown from), else `params.point`; an option naming no place (a reload, a punch) is allowed.
  `confines()` (any rule set), `room_at(p)` (`HouseRooms.key_at`), `copy()` (a copy a later refresh leaves as it is) and `view()`
  (`{ inside_only, room, leash_center, leash, confines }`). Who reads which: `sense()` puts `confinement.copy()` in the decision snapshot
  (`snapshot["confinement"]`), which the planner's COMBAT filter reads (`domain-ai-decision`); behaviour's fight (`hold_ground`), `Combat`'s
  spots and melee (`domain-ai-combat`) and the `follow` primitive (its `leash_center`) read the live one, and the reflexes' leash break
  its `leash_center` / `leash`. The controller's `debug_state()["confinement"]` is the live `view()`, its `debug_state()["decision"]
  ["confinement"]` the copy the last walk decided over. Pinned by `tests/ai/perception/confinement_suite.gd` (each rule, their
  combination, an option's place, the frozen copy), and through its answers by the game tests
  `ai/decision/combat_options_within_confinement` (the planner's filter on a hand-made snapshot) and
  `ai/combat/combat_spot_within_confinement` (Combat's spot choice).
- `agent_vision.gd` — the sight sense and the single owner of the ray query (`blocked` / `raycast`).
- `agent_hostility.gd` — the hostility rules (categorization).
- `agent_memory.gd` — a generic, behaviour-agnostic event log.
- `agent_tactics.gd` — combat geometry: flank sides, fire/advance/retreat spots, routes, cover.
- `agent_grenades.gd` + `agent_throw.gd` — the live grenades the NPC knows of and the plan to get clear of them, and the grenade geometry both that and the GRENADE tactic use (below).
- `agent_suspicion.gd` — why a room is suspect (`docs/grenades.md` G18): `rooms_suspected(rooms, lost, callouts)` -> room key -> reason ids in
  `ORDER` (`gunfire`, `footsteps`, `shot_from`, `ally_fight`, `seen_in`, `lost_by_door`, `heading_in`), `lost_rooms`, `shot_rooms` (the rooms `shot_line` runs through: the line back from a shot, counted from where it leaves the room the shot
  landed in, which is only where the NPC stood; the whole line when it never leaves that room). A pure read of the memory, the lost
  hostiles and the radio, shared by the snapshot (which words it) and, through `hearing.room_suspicion(key)`, the behaviour's entry (any entry into a suspect room is a bang one, and a late reason turns a quiet entry, E17).
- `agent_entry.gd` (+ its parts `entry/entry_posts.gd`, `entry/entry_slots.gd`, `entry/entry_layouts.gd`, and the static
  `entry/entry_landings.gd`) — doorway geometry for a tactical entry (`docs/tactical-entry.md`) (see "Entry geometry" below).
- `house_rooms.gd` — `HouseRooms`, the static room lookups over the house's rooms (`at(p, rooms)`, `key_at(p, rooms)`, `by_key(rooms, key)`) the
  perception, its snapshot, the doorway views and the entry geometry share, and how a doorway joins them: `joins(o)` (the keys of the rooms
  doorway `o` joins, as Strings) and `beyond(o, here)` (the room it leads into from `here`, "" = outside: the other room, "" for an exterior
  door gone out by, null when it is no doorway of `here`), which the doorway geometry (`entries_from`, `room_doorways`), the doorway views
  and the team (`Squad`, `attack_door.gd`) read alike.
- `stack/` (`stack_claim.gd`, `claim_ledger.gd`, `door_stack.gd`, `stack_layout.gd`) — a doorway's stack as the radio describes it: the entry claim's wire
  format and step lists, the claims one listener has heard, and every slot rule and slot point (see "The stack" below). The one folder of
  perception's that behaviour and the team (`ai/team/`) preload themselves: the stack seam.
- `agent_door_views.gd` — each doorway's view and the walk that keeps out of the views (E18), and the first doorway or view a walk comes
  to, which the entry guard secures (see "Doorway views and the walked route" below).
- `agent_snapshot.gd` + `snapshot/` — the BUILD half (`domain-ai-snapshot`): turns the gathered knowledge + the tactics geometry
  into the decision SNAPSHOT (facts / sections / option groups) and owns the measured wording Von reads. Pure transform.

The controller (`ai/goal_controller.gd`) calls `setup()` once to BUILD the internal modules, then `apply_config(tuning)`, which hands the
perception and the snapshot's vocabulary the NPC's tuning topics, read live (`NpcTuning`, `ai/tuning/`: the one authoring surface), and sets its modules' tunables straight from them (a module field is
declared where it is read, and only the modules built without the controller keep a default: `AgentVision`, `AgentMemory`,
`AgentThrow`, `AgentEntry` and `AgentDoorViews`, built by the tests and the `ai/team/` files), and `bind(character)` once it knows the
body it drives (its first `control()`) — and
re-calls `apply_config(tuning)` each decision, so a tunable retuned at runtime reaches the modules without a
rebuild that would wipe the event memory. Nothing outside this folder holds a reference to them.

## Public interface (what the orchestrator / behaviour call)

(Config: the NPC's tuning topics, handed in by `apply_config(tuning)` as `tuning` (`NpcTuning`); the perception keeps no copy of the ones it reads
itself and reads them live: `tuning.memory`'s `contact_ttl`, `familiar_with_house`, `lead_ttl` and `search_ttl`, `tuning.combat`'s
`hit_awareness_radius`, `under_fire_time` and `engage_dwell`, `tuning.senses`'s `hearing_radius` and the hearing ranges `hear_walk` / `hear_run` /
`hear_crouch`, `tuning.context.track_smoothing`, `tuning.radio`'s `callout_range` and `callout_ttl`, `tuning.entry.enabled`, and
`tuning.entry_guard`'s `enabled` and `pass_clear_time` (below each is named by its topic's name); the rest, `tuning.grenades.enabled`, `hear_grenade`
and `evade_margin` among them, `apply_config` sets on the module that reads them, each call.)

- `setup()` (build the modules), `apply_config(tuning)` (hand in the NPC's `NpcTuning` topics and set its modules' tunables from them; re-callable each
  decision), `bind(character)` (the NPC's body, which every sense and query reads from then on; it tells the hostility rules the
  body's faction and hands the body on to `AgentThrow`, `AgentGrenades` and the snapshot, each with its own `bind`). No function
  below takes the character.
- `observe(rooms)` — the SEE pass, every tick (`sight.see(rooms)`, then `house.learn_by_sight()`, over the rooms `house.take_in(rooms)` kept): one `saw_character` sighting per visible
  character (keyed, superseded while visible; renewed every `SIGHT_EVERY_FRAMES` (3, `perception_sight.gd`) physics frames, offset per NPC and target,
  for a character that stays in the view cone: the range/cone test runs every frame, so one that enters the cone is tested at once
  and one that leaves it is dropped at once, and what the NPC holds of a character it sees is at most 3 frames old; every frame while
  `sight.primed` (a primed ambusher at its post, set each tick by the controller's reflexes, `docs/leadership.md` LD15, D37);
  `tests/ai/perception/sight_follows_a_moving_target_test.gd`) carrying `pos`, a smoothed velocity track (`vel`, measured on `GameClock`; `track_smoothing` is the share taken per game frame, so a sighting several frames after the last takes the share they add up to),
  `facing`, the visible wound damage (`wound_dmg`, banded by the snapshot), `reloading`, `posture`, `ally`, inside/room, held item; the room the NPC stands in is
  remembered as searched (`visited_room`); an unfamiliar NPC learns rooms/objects by sight (it skips what it already knows
  before testing sight, and reads each known set once per pass). That look runs every `LEARN_EVERY_FRAMES` (6, `perception_house.gd`) physics frames,
  offset per NPC by the perception node's instance id so a squad does not look on the same frame, and again at the start of every `sense()`, so what
  it knows at a decision is what it sees at that moment. The characters it tests are the group `characters` (interface 7)
  under the world root, itself left out, in tree order (`sight.others()`).
- **A blinded NPC** (`Character.stun.is_blind()`, docs/grenades.md G15) sees nothing: `observe()` skips the sighting pass (no new sighting, nothing `visible`, the `_looked` state is dropped) and the learning look, so what it holds of a hostile stays where it was last seen. Contacts "age as usual" but a blind NPC cannot tell that one has gone, so `contacts.known()` / `contacts.lost_hostiles()` keep every sighting the memory still holds (`lead_ttl`) while it is blind (`_contact_ttl`); the behaviour fires blind at the last-known spot of the engaged one. It is back to `contact_ttl` the tick it sees again.
- `contacts.known(self_pos)` — characters seen within `contact_ttl` (hostiles first, then nearest),
  with `hostile`/`reason`/`visible`/`age`. The behaviour hands the whole list to its locomotion every tick: the bodies a walk goes
  round, stops short of or gives way to are these, never one the NPC has not seen (`domain-ai-behavior`, Locomotion).
  `contacts.lost_hostiles()` — hostiles last seen longer ago, within `lead_ttl` (investigation leads).
- `hearing.process_hit(data) -> bool` — a hit on/near the NPC → `under_fire` (direction + whether it
  hit), `engaged`, hostility; an ally's round (same faction) striking near it is not (it knows who fired), while one that hits it, or a
  round from a hostile or an unknown shooter (`attacker` null), is (`tests/ai/perception/ally_round_nearby_not_under_fire_test.gd`); a hit farther off within `hearing_radius` → `heard_gunfire` (a lead), but
  ONLY from a shooter not already known hostile — gunfire from a character it is fighting (or any other
  known hostile) is no mystery (COMBAT / that contact's last-seen lead already covers it), so it is not a
  lead; only an UNKNOWN shooter is. A hit on or near it from anyone but an ally also leaves `shot_from` (`{ at, pos }`: the line back
  from where the shot landed along the incoming direction to the first wall, `AgentVision.wall_hit`, at most `hearing_radius`; kept
  `lead_ttl`, keyed by where the line ends), which outlives `under_fire` (`under_fire_time`) and makes the rooms the line runs
  through suspect (`docs/grenades.md` G18).
- `hearing.process_footfall(data)` — a `&"footfall"` (interface 10) heard through walls (`docs/hearing.md` H1): the step of a character
  not of the NPC's faction (the walker's `faction`, the one non-sight read of interface 7), not visible right now, within `hear_run`
  (running), `hear_crouch` (crouched) or `hear_walk` → `heard_footsteps` (`{ pos }`, keyed per walker, ttl `lead_ttl`): a lead
  and a reason to suspect the room. `hearing.footfall_reach()` is the farthest any step is heard, which the controller drops the rest by before
  queuing them; a deaf NPC's footfalls are dropped by the controller (G15).
- `hearing.shots_from_room(key) -> bool` — the line back from a shot at the NPC (`shot_from`, from where it leaves the room it landed in: `AgentSuspicion.shot_line`) runs
  through room `key`: the entry guard reads it (E9: under fire, but for a walk into the room the shots came from, a walk goes through a doorway without an entry).
- `hearing.room_suspicion(key) -> Array` — the `AgentSuspicion` reasons room `key` is suspect for now (empty: none): what `entry.gd` reads to make an entry a bang one, at its start and on a late reason.
- `contacts.target_pos(target_id) -> Vector2` — hostile `target_id`'s last sighting, else (none bound) where the shots at the NPC came from
  (`shot_from`), else `Vector2.INF`: what a combat `callout` radios as `target_pos` (interface 10).
- `hearing.process_callout(data)` — an ally's radio `&"callout"` within `callout_range` → the NPC's `ClaimLedger` (`hear`, every
  callout: it keeps the speaker's latest entry claim, "The stack" below) and `heard_callout` (keyed per speaker, ttl `callout_ttl`). One carrying `cleared_room` (an ally cleared a room in a
  tactical entry) also teaches the room, marks it `visited_room` and `cleared_room`, so the team does not clear it twice.
- `orders.process(data) -> bool` — an `&"order"` (interface 10, `docs/leadership.md` LD5) that names the NPC in `to` and comes from its own
  side becomes its live order (memory topic `order`, permanent, keyed `live`, replacing the one it held); a `cancel` ends the one it holds;
  true when its order changed (the controller decides at once). `orders.current()` is the live order or {}; `orders.end(id, why)` ends it (`done`,
  `refused`, `cancelled`: kept in the memory as ended, so never a ttl); `orders.take_ended()` is one that ended done or refused since the last
  call, for the controller to radio (LD7). `entry.mark_cleared(key)` ends a `stack` order whose `into` is `key` as done, the NPC's own clear or an
  ally's. A `go` (LD13) replaces nothing: when the live order is a `stack` at the go's `opening` it is kept again with `go: true` (latched,
  whenever the go came), and `orders.process` returns false (no decision is forced). An `ambush` (LD15) ends `done` on first contact:
  `orders.end_ambush_on_contact`, run at the end of every `observe`, ends it when the NPC is `under_fire()` or sees a character it holds hostile
  (D18); footsteps heard and callouts are no contact. `quick_facts()` carries `ordered`, and `follows` (the var the controller sets every tick from `Squad.follows`, `docs/leadership.md` LD19; also handed to the snapshot as the knowledge's `follows`). A callout that is only an order's progress (`order_step` with no `entry_step`) is the squad's to
  hear: `hearing.process_callout` returns before the memory, so it never replaces what that ally last said it is doing (its entry claim).
- `grenades.process(data, deaf)` — a `&"grenade"` bounce / rest: marks the grenades the NPC knows as down at that spot (seen coming down, deaf or not), and one within `hear_grenade` of a NPC that is not `deaf` is heard, so known. `grenades.process_explosion(data)` forgets the grenade that went off, keeps it as `grenades.last_burst` (`{ kind, position, frame, team }`, `frame` the `GameClock.frame()` it was noted in, `team`: the NPC or an ally threw it; a bang entry waits for its stun, and an entry goes in on its own team's burst in the room, E17) and, for a stun the NPC or an ally threw, marks the hostiles it knew
within the flash radius with a clear line from the burst as `flashed` for a few seconds (`FLASH_SHARE` 0.8 of the stun's `max_blind`, 4 s, at the burst, less with distance, at least 1 s: memory topic `flashed`), which the contact view reads as `blind` (the snapshot says "blinded by a flash"). A callout whose `status` is `grenade` / `frag_out` / `bang_out` is not an ally's plan: `hearing.process_callout` hands it to the grenade tracker (`called`) and returns before the memory (so it never counts as a held flank side or an entry claim).
- The orchestrator drops what a deaf NPC would hear (G15): its callouts, hits not on it, footfalls, grenade landings.
- `check_lead(lead_id)` — the NPC reached an investigation lead: remember it as checked
  (`checked_lead`), so it is not offered again until something newer happens there.
- `quick_facts()` — cheap facts (under fire, engaged, hostile known) between decisions.
- `sense(goal, activity) -> { facts, sections, sections_per_target, options }` — the
  BUILD pass (below). `activity` is the behaviour's current-activity line.
- Combat geometry for the behaviour: `has_line_to(target, point)`, `combat_spots(target, tgt_pos, radius)` (a ring of `combat_ring_count` points),
  `note_engaged` / `engaged_fresh` / `under_fire`; `memory_size()` and
  `house.room_status(self_pos)` (each room tagged current / searched / unsearched / unknown) for debug.
- Entry geometry for the behaviour, on the `entry` part: `entry.geometry(opening_id, into)`, `entry.stack(opening_id, into := "") -> DoorStack` (the doorway's
  stack as the radio describes it, built by the NPC's own `ClaimLedger` over that geometry, one per doorway a frame: every slot rule the entry
  reads, `claim`, `slot_for`, `settle`, `split_side`, `back_slot`, `crossing` / `ahead` / `behind`, `thrower`, `order_claim`, `released`,
  `move_up_vacancies`, `team_side`, with `StackLayout`'s statics over its `geometry` beside it (`holds_slot`, `is_tail`, ...); with `into` "" it has no geometry and answers only what the claims alone do, `team`, `claimed`, `stacking`, `going_in`,
  `released`, `crossing`, `order_claim`; "The stack" below),
  `entry.side_of(geo, p)` (the side of the door `geo` (its geometry), 1 / -1 along its wall, a point is on: the radio claims' `side`),
  `entry.stack_side(door_stack)` (the side the NPC stacks on from where it stands in that `DoorStack`: the team's, or its own when its way
  there crosses the doorway's view, E19), `entry.on_stack_side(geo, p)` and `entry.slot_reach(to, bodies)` (from where the NPC stands,
  `AgentEntry.slot_reach`, below) (wrappers on `AgentEntry`, which the snapshot's `entries` and `order` groups also use; the behaviour never
  reaches into `agent_entry.gd` itself, but preloads the stack module, `StackClaim` and `DoorStack`, the seam it shares with the team; the
  other consumers are the human's `PlayerStack` and the `Squad` in `ai/team/` (`domain-ai-team`), which use `AgentEntry` directly through
  its published seam, `set_house`, `geometry`, `stack_side_from`, `slots.on_stack_side`, `opening_id` and `normal_into`, and the stack module
  (`StackClaim`, a `ClaimLedger` of their own, the `DoorStack`s it builds and `StackLayout`) for every claim and slot) (below). `views.avoided()` (the doorway views the NPC's walks keep out of from where it stands, E18, each `{ id, into, poly }`, `[]` while `avoid_views` is off: the entry guard's read-out). `house.openings` (the house's doorways, set by the controller each tick from Main's inject); `observe` calls `AgentEntry.warm_geometry` each SEE pass while `tuning.entry.enabled`.
- `contacts.all_seen_characters()` (every character seen, allies included), `debug_memory()` (the event log for the brain overlay and
  gcmd: `gunfire`, `footsteps` and `shot_from` among it, each `[{ pos, age }]`, `shot_from` with `at`) and `fill_goal(goal)` (the goal with `{gun}` filled in).
- `sight.visible_points(points) -> Array` — of `points`, the subset in sight right now (view
  cone + clear line of sight, via `can_see`); the searcher's room-coverage test (behaviour samples a
  room and asks each tick which sampled points it has now seen).
- `sight.sight_end(to) -> Vector2` — where its sight toward `to` is first blocked (`AgentVision.sight_hit`, over
  low cover), or `to`; the controller's `debug_sight_end` forwards it to the vision overlay.

## The snapshot and the wording rules — `domain-ai-snapshot`

`sense(goal, activity)` gathers the knowledge (contacts, callouts, learned rooms/objects, lost hostiles) and hands it to
`agent_snapshot.gd`'s `build(...)`, which assembles the snapshot the planner walks (facts, state sections, option groups) and owns the
measured wording Von reads. That whole sub-domain — `agent_snapshot.gd` and `snapshot/` (vocabulary + tuning, sections, option groups), the
fact / section / option reference and the Von wording rules — is the **`domain-ai-snapshot`** skill.


## Contacts and hostility

The NPC perceives characters, not "the player". The hostility rules categorize each sighting: allies
(the same faction) are never hostile; `on_sight` / `trespass` (seen inside the house)
/ `retaliate` (attacked it, via `hearing.process_hit`), set from `tuning.hostility` (`on_sight`, `on_trespass`, `on_attack`). A verdict is remembered as
`&"hostile"` with ttl `tuning.hostility.ttl` (≤ 0 = permanent grudge).

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
sim's pace (a contact's 4 s are 4 s of sim). The rest of the perception's ages read it too: the sightings' velocity track, `grenades.last_burst`'s
`frame`, the grenade replan, `views.routes_ready`'s `WARM_CAP_MS` and `debug_memory`'s `left`. `tests/ai/perception/memory_matches_reference_test.gd` runs random writes through the memory and a plain ordered log and compares every reader. Topics: `saw_character` / `saw_room` / `saw_object` / `visited_room` /
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
front, so a route behind its back is hidden — `_route_exposed`'s optional `front`), `crosses` (a known
hostile the route passes), `held_by` (ally within `flank_ally_radius` on that side, or a callout point
there), `exposed_to` (other hostiles), `heading_toward` and `ally_lane` (a seen ally whose line of fire
on the target passes within 40 px of the spot, or that the route there crosses). Hostile fronts
(`ctx.fronts`, built once per `sense()`) serve both the flank frames and the watch test below. The
snapshot turns these into boolean tags on each `flank_sides` option — `held`, `crosses`, `no_shot` (no
clear shot), `heading`, `lane` — which the `flank` node's `drop_tags` drop; the side stays in
`debug_zones()` with its words ("line blocked from there", "they are moving toward that side", "in X's
line of fire").

Route safety: `_route_crosses(path, hostiles)` names a hostile whose last-known position lies within
`route_clearance` of the route AND nearer than the route's start (walking away from someone close by
is not passing them). `_watched_in_open(ctx, p, path)` names a hostile that would catch the NPC in the
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

**Throw spots** (`throw_spot(ctx, aim: ThrowAim, ex)`, `ThrowAim` (`ai/perception/throw_aim.gd`) carrying the `spot`, the `reach`, `keep_out`, the `lob` test and the `route`, issue #51 R13 / R15, `docs/grenades.md` G17): where to throw onto `spot` from when the lob
from where the NPC stands fails (out of range or not clear). Candidates on rings round the NPC (`THROW_RINGS` 48 to 240 px, `THROW_DIRECTIONS` 16, none past
`throw_spot_walk`) and round the spot (`THROW_REACH_SHARES` 0.95 / 0.8 of `reach`), cheap tests first (straight distance under `throw_spot_walk`, snapped onto the
navmesh within `SNAP_TOLERANCE`, within `reach` of the spot, more than a `STRIDE` away, not inside `keep_out` (the room the hostile holds, or the shots' room),
the `lob` callable: `AgentThrow.throw_clear` from there), then sorted as the fire spots are: hidden from the spot (`blocked`: low furniture between), then with
cover close by against it (`_cover_near`: a jamb, a piece), then the straight distance; routes only for the first `THROW_ROUTES` (10), through the optional `route`
callable (`{ path, len, detour }`: the snapshot's `_throw_walk`, the walked route of `AgentDoorViews.walk_route` and whether the entry guard would stop it), kept when
the route reaches it, is at most `throw_spot_walk` (250 px, `tuning.grenades.throw_spot_walk`) and passes no known hostile (`_route_crosses`); the pick is
the first with no `detour`, then hidden, then covered, then the shortest walk. `{ point, route_len, hidden, cover, detour }` or {}. Cost: ~150 snaps and lob tests and up to 10 routes, only for a throw the NPC cannot make where it stands.

## Entry geometry (`agent_entry.gd`)

The behaviour asked of it is `docs/tactical-entry.md`. Given the house's openings (Main's `WorldGen.get_openings`, handed
in by `set_house` on each observe) and rooms, `entries_from(room_key)` lists the doorways out of the NPC's area (outer
doors from outside, a room's doors into the next room), `watch_doors(room_key, exclude_id, is_cleared)` those of a cleared
room on into rooms not cleared (what the team covers after clearing it, E8; the perception's `entry.watch_doors(into, opening_id)`) and `geometry(id, into, map, space)` lays one out, built once on a
baked nav map and cached (walls do not move): `out` (unit normal away from the room, from the room edge the door lies on)
and `along` (the wall's axis), `wall` (wall length either side), `side` (the side with more wall, 0 when even; once the slots are laid, the side whose file holds more against the wall when they differ), `slots`
(single file against the wall on each side: `wall_standoff` off it, the first a body clear of the jamb, then every
`stack_spacing` (44 px: clear of the neighbour's footprint, outside the 34 px hole a body at rest on the next slot cuts in the
steering map, so a slot is never a destination inside a teammate), snapped), `pie` (`pie_steps` points `pie_radius` from the threshold, from 55° to 25° off the axis), `lookouts` (the slots and pie points as laid out, before they are snapped
onto the navmesh: where an entry's stack and point stand, or near it; what an ambush post is hidden from), and the
`capacity` (how many go in: 2 when a side of the room is under `short_room`, the NPC's `tuning.entry_geometry.short_room`, else `MAX_SLOTS`: E13), the
room's four corners inset `corner_inset`, each `near` (on the door's wall), `side` and `hard` (no sight line from 24 px
outside the threshold). The claims and every slot rule that reads them (which slot is free, the team's side, a member's side and place,
its point, the crossing order) are not `AgentEntry`'s but the stack module's (`stack/door_stack.gd`, "The stack" below); `AgentEntry` keeps
the doorway's geometry. **A split stack (E19):** `stack_side_from(stack, from, map, space)` is the team's side (`DoorStack.team_side`)
unless `cuts_view(g, from, to, map, space)` (the plain route from `from`, starting outside the doorway's view, `views.door_view`, crosses the door's axis inside the view: a walk
that starts in the view or goes round it does not) says the way there crosses the view; then the member's own side (`side_of`). An `AgentEntry` built outside the perception (`PlayerStack`'s, the `Squad`'s) makes its own `AgentVision` and `AgentDoorViews` for the view rays. Tunables: the NPC's `tuning.entry_geometry`.

**Where a stack stands (E20 to E22, `slots.lay`).** On a baked map with a physics space `_build` also lays the slots: `from` / `from_room` (the
room the stack stands in, "" / a zero rect outside), `kind` and its layout, `wall_n` (how many slots the wall, or the fewest-seen spots,
hold), and past them `seq` (the overflow: open floor, then the tail from `tail_from`) and `capped`; `spacing`. `kind`: `wall` (a spot against
the wall beside the door out of every other doorway's view, `_has_wall_spot`): `files { 1: [{ point, row }], -1: [...] }` packed exactly at
`stack_spacing` from the wall band (`_band`: `SLOT_BODY` past the jamb to the stack room's corner, outdoors `OUTDOOR_REACH` 320 px, or
another doorway's funnel; `SLOT_OUT_MIN`–`SLOT_OUT_MAX` 14–110 px out; `WALL_GRID` 8 px, on `SLOT_STEP` 4 px when short of a full stack;
`_pack` / `_most_spaced` within `PACK_BUDGET` steps), `row1` (how many of each against the wall, within `ROW1_DEPTH` 50 px) and `g["side"]`
from those counts; `views` (every wall spot is in another doorway's view): `views_lays`, each stack size on each first side from the points
seen by the fewest doorways; `open_floor` / `dead_end` (no wall spot; `dead_end` when the stack room has no other doorway). A point is kept
only on the navmesh within `SLOT_SNAP`, inside the stack room by `SLOT_ROOM_INSET`, on the stack side, reached from `SLOT_REACH_OUT` out
without going through the doorway, out of other doorways' funnels (`StackClaim.in_funnel`, the one funnel test) and, but for `views`, their views (`VIEW_MARGIN`); a
navmesh carved round solid furniture skips it (E22). `_overflow`: `_open_floor` (`OPEN_GRID` 8 / `OPEN_GRID_FINE` 4 px; outdoors within
`OUTDOOR_FLOOR` 300 px; past a short wall or a `views` way in, `strict`: off the wall band and out of other doorways' views; exact when
capped), then `_tail_spots` (in the room beyond the stack room's nearest other doorway, within `TAIL_REACH` 140 px of it); `capped` (a dead
end, or outdoors past a short wall) takes no tail. The layout statics every stack reads from this geometry (`slots`, `side_for`, `point`, `holds_slot`, `is_tail`) are
`StackLayout`'s ("The stack" below). The laying is `AgentEntry`'s part `slots` (`entry/entry_slots.gd`, `EntrySlots`, built once with it,
holding nothing of it: `slots.lay(entry, g, opening, map, space)` and `slots.on_stack_side(entry, g, p)`, the entry handed in at the call;
`slots.frames`, every way into a room framed, cleared by `set_house`). Its helpers over the style's five parameters (`_overflow`,
`_open_floor`, `_slot_ok`) read the entry from the stack context they already take (`c["entry"]`, set by `_stack_context`), which dies with
the call.
**Shared, and laid ahead.** `geometry` keeps each doorway's layout in its part `layouts` (`entry/entry_layouts.gd`, `EntryLayouts`, built
once with it, holding nothing of it): in the instance's `layouts.cache` and in the static `_shared` (`layouts.shared_on(map)`: navigation map
RID -> `"<layouts.key(entry)>|<id>><into>"` -> geometry, `key` being `tuning_inputs(entry)` (the house and the tunables `_build` reads) as a
string), dropped when the map's planning region leaves the tree; only a layout snapped on a baked map is kept. `warm_geometry(map, space)`
lays at most one missing way in per physics frame among every NPC (the static `EntryLayouts.warmed_frame`), so a house's doorways are laid in
the frames after the bake, not in a decision. Once a pass finds every way in laid it remembers that shared dictionary and the
`tuning_inputs` array (`layouts.warm_done_in`, `layouts.warm_done_for`) and returns at once until either changes: comparing the array costs about 0.2 us against about 3 us to format the key, and
scanning every opening x room per NPC per tick cost 0.1 to 0.2 ms a frame in the match guards. Laying one way in costs 7 to 52 ms
(garage_home's ten: `_band` 2 to 15 ms, `_overflow` 10 to 28 ms); all ten are laid by 0.22 s into a match, before the perf guards measure
(`docs/leadership.md`, Performance).

**Cleared rooms and the entry guard (E9).** `cleared_room` (keyed per room, ttl `search_ttl`) is not `visited_room`:
standing in a room visits it, but a room is *cleared* only by `entry.mark_cleared(key)`: the behaviour calls it when an entry
finishes (`Entry.hold.finish`, own clear or an ally's; `domain-ai-entry`) and when a search covers its room by sight, and `hearing.process_callout`
when an ally radios `cleared_room`. `entry.is_cleared(key)` reads it; the snapshot's `entries` group skips only cleared rooms
(search ranking still uses `visited_room`). `views.threshold_ahead(path, from_idx, max_dist)` (a thin wrapper on
`AgentDoorViews.threshold_ahead`) walks a nav path and returns the first doorway whose wall plane a step crosses, within the
doorway's width and heading into a room that is not the one the NPC is in and is not cleared: `{ opening, into, dist }`, or
{}. The last step is extended by `THRESHOLD_EXTEND` (30 px) so a destination that is the doorway counts. The behaviour's
entry guard calls it every tick. `views.passing_ahead(path, from_idx, max_dist)` (over `AgentDoorViews.passing_ahead`) is its sibling for E15 / E18:
the first doorway **view** the walk comes into from outside it (any doorway into a room not clear for passing: inside the house or out, exterior doors too, however far out from the wall; not the NPC's own room, nor a doorway of a room the walk goes into by any of its doors, which the entry into that room covers): `{ opening, into, dist }` (`dist` = px of walking until it is in the view), or {}.
**Doorway views and the walked route (E18, `agent_door_views.gd`).** The perception builds one `AgentDoorViews` and hands it to its
`AgentEntry` (`views`, which `set_house` forwards the house to, and which `cuts_view` reads) and to the snapshot's options; `AgentEntry`
keeps `opening_id` / `normal_into` as one-line forwards to it, so the views never preload `agent_entry.gd`. `door_view(id, into, map, space)` is the view out of a doorway (the area outside it
seen from inside room `into` through it): a polygon from the rays from the room's two far corners through the opposite jambs, `door_view_depth` (450 px) long,
each ray a fan cast from three points in the gap (the middle and each jamb, `VIEW_APEX_OUT` 8 px off the wall plane) and stopped at the first wall
(`AgentVision.wall_hit`: static bodies only, furniture and characters are looked through), the three fans fused, and for a doorway between two rooms cut at
the edge of the room in front of it (so a view does not run on through the next doorway into another room). Laid out once per doorway on a baked map and kept. `avoided(here_key, map, space, exempt)` is the set of views a walk from room `here_key` keeps out of: those of every doorway into a room that is not
clear for passing (`AgentPerception.views._is_pass_clear(key)`: the `cleared_room` memory's age is within `tuning.entry_guard.pass_clear_time`, 60 s; `entry.is_cleared` stays the
entry's), other than the NPC's own room; with `entering` (`"<opening>><into>"`, the entry a walk is the approach of) that doorway's own view
always counts, from inside the room too and cleared or not; `{ key, holes, views }` (each view `{ id, into, poly, joins }`, `joins` the rooms the doorway joins), worked out once a physics frame.
`walk_route(from, to, map, space, entering)` (over `AgentPerception.views.walk_route(to, entering, from)`) is the route the NPC walks: the plain one, unless it comes
into one of those views (or, with `entering`, goes into the room being entered) and the route on `NavBuilder.avoid_map` for the set (less
the views `from` stands in, `_left_from`; when that route goes into the room being entered, the route on the map with the room's floor carved too, `_with_room`, so the room-carved map is asked for, baked and kept only while an approach needs it) reaches `to` (within `AVOID_REACH` 24 px) no longer than `door_avoid_ratio`
(2.0) x the plain length + `door_avoid_slack` (300 px); failing that, with `entering`, the route round that doorway's own view and the room
at least (`_entering_set`), capped the same unless `ordered_approach` (set by `views.sync_walks` from `views.ordered`: uncapped, D4):
`{ map, path, len, plain_len, doors, pending, views }` (`len` the whole walk, the steps onto the route and from its end to `to` included;
`pending`: the plain route crosses a view and the avoid map is still baking). `warm(from, map, space)` (over `AgentPerception.views.routes_ready()`) asks for the avoid map of the room the NPC is in and
says whether it answers; the controller starts no decision before it does (at most `WARM_CAP_MS` 3 s of game time), so the route bands a snapshot reads are the walked ones.
`AgentEntry.slot_reach(from, to, map, bodies)` (over `AgentPerception.entry.slot_reach(to, bodies)`) is whether any way at all reaches `to` with a body standing at each
point of `bodies` at body width (a `BODY_SEGMENTS`-gon of `SLOT_BODY` + `NavBuilder.OBSTACLE_MARGIN` each, the steering map's carve of a body at rest, on an
`NavBuilder.avoid_map` of their own keyed by the bodies on a 4 px grid): 1 when its route ends within `AgentDoorViews.AVOID_REACH` of `to`, or within
`AgentEntry.LAST_LEG` (64 px) of it with the plain way on from there that long at most and passing none of `bodies` closer than
`AgentEntry.pass_limit` allows (`PASS_CLEARANCE`, 32 px: the walk's own numbers, held here once and read by loco_crowd's `LAST_LEG` and
Locomotion's `PASS_CLEARANCE` instead of copied: Locomotion's last leg, the way into a slot between two taken ones, which lies inside their carved margins); 0 when not, -1 while that map
bakes (asking starts it), 1 with no planning region or the plan map not baked yet (no verdict: not sealed). It is what the entry asks before it reads a hold as sealing its slot (E2, `domain-ai-entry`).
Config (the NPC's `tuning.entry_guard`, through `apply_config(tuning)`): `door_view_depth`, `door_avoid_ratio`, `door_avoid_slack` (set on `AgentDoorViews`), `pass_clear_time` (read live by the perception); views are
avoided only where `tuning.entry.enabled` and `tuning.entry_guard.enabled` are.
**Defend spots (`docs/leadership.md` LD8, D2).** `AgentEntry`'s part `posts` (`entry/entry_posts.gd`, `EntryPosts`, built once with it,
holding nothing of it) lays the posts an order stands at, the entry handed in at the call, and the member's place in its order as one
`Vector2i` (`place`: x `nth`, which post, y `count`, of how many). `posts.defend_spot(entry, room_key, place, map, space)` is where member `nth` of `count` ordered to
defend a room holds it: the room's doorways sorted by id, member `nth` taking doorway `nth` mod their number (the extras doubling up on its
other side), the spot `DEFEND_DEPTHS` back from its wall and `DEFEND_LATERALS` past its jamb (best 100 / 50 px), inside the room by
`DEFEND_INSET`, snapped onto the navmesh, scored out of every doorway's fatal funnel first (within `DEFEND_BODY` of its width, nearer its wall
than `DEFEND_FUNNEL_DEPTH`), then with a sight line to its doorway, low furniture on that line (cover seen over), its side and the distance
from the best; a lone member of a room with several doorways takes the spot that sees the most. `{ spot, door, door_pos, doors }` (`door` ""
and `door_pos` INF for that lone member, who turns among them). The snapshot's `order` group calls it. `AgentEntry`'s `static normal_into(rect, pos)` (the
unit normal into a room from the edge a doorway lies on, `AgentDoorViews.normal_into`) is also read by the squad (`ai/team/squad.gd`).
**Ambush posts (`docs/leadership.md` LD15, D17).** `posts.ambush_spot(entry, g, place, map, space)` (`g` the entry geometry `geometry(id, room_key, map, space)`) is where member `nth` of `count` ordered
to ambush doorway `id` from room `room_key` waits: `{ spot, door_pos, seen }` (`door_pos` the doorway's centre, where its gun goes; `seen` how
many lookouts see the post, 0 hidden), {} for a doorway or room it does not know or no post. The candidates (`_ambush_ranking`: `{ posts,
landings }`, kept per doorway and room side once worked out on a baked map, in the NPC's `posts.cache`, cleared by `set_house`, and **shared
by every NPC on the map** in the static `_shared` (`EntryLayouts.per_map`: map RID -> `"<layouts.key(entry)>|<crouch>|<id>><room>"`,
dropped with the map's planning region), since a doorway's ranking reads nothing of the member but the tunables that key names (the
geometry's and the sight's, and the crouched height) and the characters' bodies are looked through; `_ambush_post` reads the entry from
the frame it takes, `f["entry"]`, set by `_ambush_ranking`) lie `AMBUSH_DEPTHS` (40 to 160 px) back from the
wall and `AMBUSH_LATERALS` (30 to 260 px) past the jamb, either side, inside the room by `AMBUSH_INSET` (22 px), through `_defend_candidate`
(snapped, its funnel, its sight line and cover on the line to each doorway, the characters' bodies looked through); one off the doorway's sight line or on its axis (within half the
width + `DEFEND_BODY`) is dropped. Each is scored `seen` x `RANK_SEEN` (1e7) + frag landings x `RANK_FRAG` (1e5) + stun landings x
`RANK_STUN` (1e4) + funnel x `RANK_FUNNEL` (500) + (no cover on its line to the threshold) `RANK_NO_COVER` (300) + |depth - `AMBUSH_DEPTH`
110|, each rank above all the ranks below it can add up to; `ambush_spot` adds `RANK_SIDE` (1e9) for a post off the member's side, above
everything. Since nothing below `seen` can outweigh one `RANK_SEEN`, the landings are counted only where they can decide a pick
(`_best_post`): among the posts still open (clear of the posts taken) only those tied on the least `seen` and side can win, and only
those have their exposures counted (`_expose`, once a post, kept in the ranking), so the picks are those of the full score
(`ai/combat/ambush_posts_capture_terrace` / `_house` pin every post of two houses to a capture of the full ranking). `seen` counts the geometry's `lookouts`, slots and pie points that see it (`_sees_from`: `AgentVision.sight_hit`, over low cover,
at any range and facing); a post seen by none is hidden only if it is hidden from the 8 points `AMBUSH_SLACK` (12 px) round it too. The
landings (`_exposures`, LD15, D17) count, per kind of `BANG_KINDS` (frag, then stun), the spots an entry's grenade into the room by that
doorway may land (`_bang_landings`: `EntryLandings.spots(g, reach)`, reckoned from the doorway's centre, no slot filter) that reach a body
crouched at the post: within the kind's `danger_radius` and not shielded by `Explosion.shields` (interface 3) with a `CoverRule` at
`posts.crouch` (the body's `movement.posture_coverage(&"crouch")`, handed in by `AgentPerception.bind`), every character under the NPC's world root excluded
(`_bodies`: the group `characters` under `posts.body`'s `world_root()`, interface 7, the NPC's body handed in by `bind` beside `crouch`;
none for a geometry built with no NPC), `cover_reach` the kind's `flash_cover_reach`. The grenade's numbers are `GrenadeConfig.stats_of(kind)` (interface 6: a grenade
nobody holds), the reach a thrower that knows the grenade has (`AgentThrow.reach_of` of an `AgentThrow` that `learn`ed those numbers: `max_range` less `REACH_SLACK`). Members alternate sides of the axis, the side with more wall first, and
two posts stand `AMBUSH_SPACING` (44 px) apart. The snapshot's `order` group calls it.
**Where an entry's grenade lands (`entry/entry_landings.gd`, `EntryLandings`, static, preloaded, no `class_name`; `docs/grenades.md` G18).**
The one rule the stack's thrower aims by (the behaviour's `entry/entry_grenade.gd`, `domain-ai-entry`) and an ambush post is shielded by, over
a way in's entry geometry `g`: `grid(g)` the aim points in order of preference, `Vector2(deep, across)`, `BANG_DEPTHS` (0.85 / 0.7 / 0.55) of
the room's depth (`room_depth(g)`, to its farthest corner along the axis) by `BANG_ACROSS` (0 / 0.2 / -0.2) of its width; `aim(g, spot, at,
reach)` the point a grenade thrown from `spot` lands at, pulled back along its line to within `reach` (`Vector2.INF` when no point that far
across is); `lands(g, target)` inside the room `BANG_INSET` (30 px) clear of its walls and at least `BANG_MIN_DEPTH` (120 px) from the
doorway; `spots(g, reach)` every aim point aimed from the doorway's centre that lands, deduplicated.
**An ordered stack's walk (`docs/leadership.md` LD9, D4, D11).** `views.ordered` (on the perception's `views` part, `perception_views.gd`; set each tick by the behaviour while it walks an ordered stack's
way to its door) makes `sync_walks` turn the view avoidance on (`AgentDoorViews.avoid_views` = `tuning.entry_guard.enabled` and (`tuning.entry.enabled` or `ordered`))
and, for an NPC with `tuning.entry.enabled` off (a defender), swap `AgentDoorViews.pass_clear` for `_passable` and have `threshold_ahead` pass rooms
`_seen_empty(key)` says it stood in within `pass_clear_time` with no hostile sighting in them (the latest of each hostile it knows, within that
time); `avoided` keys its per-frame cache on the `pass_clear` rule too. On an ordered walk the room its stack holds is clear too: `_stack_room()`
(once a physics frame: the live order is a stack, `ordered`, and a claim on its doorway under the same `order_id` is at `ready` / `bang`
→ the geometry's `from`, the steps `StackClaim.IN_SLOT`; else "") counts as cleared for `threshold_ahead` and as pass-clear (`_pass_clear_ordered`, handed as `pass_clear` to
an ordered walk with entry on; `_passable` adds `_seen_empty`), D20. An invader's walks are otherwise unchanged. The team's claims (`StackClaim.decode`)
carry an ordered member's `order_id`, `order_bang`, `order_mode` (LD14), `order_hold` and
`order_go` (LD13), `order_side` and `order_frame` (the frame the order was issued on, D14) ("" / false / quiet / false / false / 0 / -1
for others), which `entry.gd` reads, and every member's `crossed_frame` (the frame its crossing began on, -1 before it).
`entry.room_doorways(room_key)` (over `AgentEntry.room_doorways`) lists every doorway of a room, outer doors
included, as `{ id, pos, width }`: the places a resting NPC watches (`Watch.idle_gaze`, `domain-ai-watch`).


## The stack (`stack/`: `stack_claim.gd`, `claim_ledger.gd`, `door_stack.gd`, `stack_layout.gd`)

A doorway's stack as the radio describes it (`docs/tactical-entry.md` E2, E6, E16 to E22; `docs/leadership.md` LD13, LD18), held once for
every reader: the NPC's entry and its snapshot, the human's `PlayerStack` and the side's `Squad` (`domain-ai-team`). Behaviour, the
orchestrator and the team preload these files themselves; this folder is that seam.

- **`StackClaim`** (`stack_claim.gd`, static, preloaded, no `class_name`): the entry claim's wire format on the `&"callout"` radio (interface
  10). `DEFAULTS` holds every entry field with the value a claim that does not say it has (`bang` true, `stuns` / `frags` 0, `claim_frame`
  -1, `claim_pos` `Vector2.INF`, `order_mode` `quiet`, `order_frame` / `crossed_frame` -1, ...). `encode(fields)` gives a callout's entry fields (every one, typed; the producer
  adds its own header): the controller's radio (`npc_comms.gd` `post_entry_call`) and `PlayerStack._post` call it. `decode(data)` gives a callout's claim, `{}`
  for none (no `entry_step`), with `step`, the speaker's `id` / `name`, `pos` and `age`, and `claim_pos` where the speaker stands when it says
  none. `is_claim(data)` (any entry step, `abort` / `done` too: it replaces what the speaker last claimed); `keeps_claim(data)` (a live-grenade
  call, `AgentGrenades.is_call`, G16, or an order step with no entry step, LD7: the speaker's last claim stands; any other callout drops it);
  `is_join(d)` (an order, a leaf's params or a claim of a join, LD24: the one test of it). The step lists `STACKING` (`claim`, `ready`,
  `bang`, `going_in`), `IN_SLOT` (`ready`, `bang`), `THROUGH` (`in`, `clear`, `cover`, `rear`), `CLEARED`, `HOLDING`, `ENDED` and their
  tests `stacking` / `in_slot` / `through` / `cleared` / `holding`, and `crossing` (`going_in` or a `THROUGH` step); the distances `THROUGH_DEPTH` (26 px), `FUNNEL_DEPTH` (40 px, the funnel of `in_funnel(outward, lateral, half, margin)`, the one funnel test the slot rules and `PlayerStack` call),
  `HEARTBEAT` (2 s), and the two reaches named apart, `SLOT_REACH` (6 px: an NPC walks all the way into its slot, since a stride short of it
  stands on the next one) and `HUMAN_SLOT_REACH` (20 px: how near a hand-driven body counts as in its slot); `JOIN` (`join`); `by_slot`, the
  one comparator claims are sorted by (lowest slot, then lowest instance id).
- **`ClaimLedger`** (`claim_ledger.gd`, `RefCounted`, one per listener: the perception's `entry.ledger`, `PlayerStack`'s, the `Squad`'s):
  `setup({ faction, range, ttl, listener })`, `hear(data, listener_pos := Vector2.INF)` (its side only, within `range`, <= 0 unlimited,
  the squad's whole view; never the listener's own; `keeps_claim` leaves the speaker's claim standing, any other callout replaces it),
  `claims(opening)` (the live decoded claims, one per speaker, none `ENDED`, `by_slot`, `age` set; shared until the next frame: never
  changed), `stack(opening, g := {}) -> DoorStack` (built at most once a physics frame per doorway and room, or again once a claim is
  heard) and `openings_stacking()` (`{ opening, into }` for each doorway with a live `STACKING` claim, `into` the lowest-slot
  stacking claim's). A claim lapses `ttl` s after it was heard, on
  `GameClock` (LD1), and a dead or freed speaker's goes at once.
- **Stale claim.** The ledger keeps each speaker's latest claim, whichever entry it was made for: a claim from the team's
  last entry through a doorway still stands while the next one forms there. A rule that reads a claim names what makes it
  the current entry's: its `order_id`, its `into`, or a frame since (`order_frame` / `crossed_frame`, as `released` scopes
  the human's crossing by the order's frame). Its test includes a claim left from an earlier entry through the same
  doorway, which counts for nothing.
- **`DoorStack`** (`door_stack.gd`, `RefCounted`, `new(geometry, team)`): the doorway's `geometry` (`AgentEntry.geometry`; {} for the
  claims alone) and its claims (`team`), every slot rule settled the one way for whoever asks. A member asking about itself passes `me`,
  its own claim as it stands (`{ id, slot, side, want, frame, pos, move_up, stuns, frags, order_*, step }`, each optional): it never hears
  its own on the radio. `slot_for(me)` (E2: the lowest free slot, `StackLayout.free_slot`; two claims on one slot made on the same frame and side settle
  by distance to the slot's point, laid among the rest, `StackLayout`'s `_verdict` / `_settles`, within 0.5 px or otherwise the lower instance id, and a slot claimed on
  that frame by someone farther is taken from them, so the settling runs down the stack; a move-up holds against a plain claim and its
  holder takes the freed slot); `settle(me) -> { slot, side, place, point }` (E19 to E22, with the move-up rewrite, `_moved_up`: a claim
  still on a slot a member moved up into counts at the slot that member freed, for every reader); `points(me)`; `layout(me := {})` (the
  markers' `[{ n, point, holder, held, there, mine, side, row }]`, the same points `settle` gives); `crossing(me := {})` / `ahead(me)` /
  `behind(me)` (E6, E19); `claimed()`, `stacking()` (a claim at a `STACKING` step: one on its `bang` still holds a place), `going_in()`;
  `thrower(kind, me := {})` (E17, LD14: slot 2 if it carries one, else the lowest slot that does; never the human); `order_claim(me := {})`
  (LD9: `me`'s order, its `order_frame` and `into` too, else the lowest slot's that carries one, D10); `released(order_id, into, since)`
  (LD13, `_releases`: a claim under the order says `order_go`, or a member of that stack, a claim under the order or the human's, is
  crossing or through into room `into`, D14, the human's only on a crossing begun on or after `since`, the order's frame: its
  `crossed_frame` at or after it, since the human's claim carries no order to scope it by, and a -1 on either releases nothing; a claim
  left from an earlier entry through the doorway, under no order or another, or into the other room, releases nothing);
  `team_side(from)`; `claim(me, want) -> { slot, held, side, place,
  point }` (the chain every member claims and keeps its slot by, an NPC's entry (and the slot its snapshot's `entries` group offers it) and the human's `PlayerStack` alike: `slot_for`,
  `held` = `StackLayout.holds_slot` over its geometry, E20, the side asked for in that slot, `want` called with it, the member's own weighing, then
  `settle`; a member whose slot changes is no longer moving up); `split_side(me, own)` (D6, E19: `own` unless that side would hold two
  more than the other with `me` there, when its last claimer, the highest slot then the highest instance id, takes the other);
  `back_slot(slot)` (E2: the slot behind the last claimed, 0 when `slot` is the last already or the doorway has no slot there, E20);
  `order_place(to_ids, self_id)` (E20, LD9: an ordered member's slot, after the order's living recipients named before it and every claim
  from anyone else, so a dead end's extras are known before anyone claims; ids only, it holds no nodes); and
  `move_up_vacancies(me)` (E2, the rule part: each lower slot on `me`'s side whose holder is at `claim`, not the human's nor moving up
  itself, its slot staying on `me`'s side with the two swapped, as `{ holder, slot, point, stack }`; none once a claim says `pie`, `bang`,
  `going_in` or through; the walk and the latecomer are the entry's).
  Read-only: it never changes the claims it was built from.
- **`StackLayout`** (`stack_layout.gd`, static, preloaded, no `class_name`): the layout and claim rules, the one place a slot becomes a point,
  which `DoorStack` settles its doorway by and the entry, the snapshot and `PlayerStack` read beside it:
  `slots(g, count, side) -> [{ n, point, side, row }]` (only as many as `holds_slot`), `side_for(g, claims, slot, preferred)` (E21:
  its side while that side's row 1 has room, else the other's, then a second file on its side, then the other's; past `wall_n` or with no
  files, the side the slot lies on), `point(g, members, slot, side)` (INF for a slot a dead end does not hold), `place(claims, side,
  slot)` (a member's place in its side's file: its slot less the claims ahead on the other side), `crossing_order(members)` (by slot, or
  on a split stack the point, the other side's front man, then the sides in turn), `stack_side(g, claims, self_pos)` (the point's side,
  else `g["side"]`, else the member's own), `holds_slot(g, slot)`, `is_tail(g, slot)`, `free_slot(claims, self_id, current, mine)`,
  and `laid(g, members, slot, side)` / `on_wall(g, slot)` (a slot's `{ point, row }` and whether it stands in a file against the wall,
  which `DoorStack.layout` reads). `NO_FILE_OUT` (28 px): how far out in front of the door a slot stands when the
  doorway has no file to lay it in.

Two unit suites (`UnitSuite`, plain claim dicts, beneath the simulation tests per ADR-0002) pin the module: `tests/ai/stack_claim_suite.gd`
the codec and the ledger, `tests/ai/door_stack_suite.gd` the slot rules.


## Grenades (`agent_grenades.gd`, `agent_throw.gd`; spec `docs/grenades.md` G15, G16)

**What it knows (`agent_grenades.gd`, `grenades.known()`).** A live grenade is a node of the group `live_grenades` (Items: `kind`, `fuse_left()`,
`throw_stats()`, `thrower`). The NPC knows one by **sight** (`observe`, every tick, only while the group is non-empty: in the view cone with a clear sight line;
its `point` follows the grenade), by **hearing** it come down (`hear`: a `&"grenade"` bounce / rest within `hear_grenade` 300 px, not deaf; the point is where it
landed), by an ally's **callout** (`called`: the `point` the call names, within 150 px of a live grenade of that kind) or because it threw it (**own**: `thrower` is
the NPC; always known, blind or not). A grenade keeps the source it was first known by (a later sighting, landing or call only keeps its spot true). Each is `{ point, kind, fuse_left, fuse, radius,
source }` (`radius` = `AgentThrow.radius_of(kind)`, off the `throw_stats()` just learned from that grenade); it is forgotten at the burst (`&"explosion"`, or the node leaving the group). A bounce / rest event marks a known grenade `landed` (and `rested`) at that spot.

**The danger zone and the safe spot (`agent_throw.gd`).** The cover rule is the blast's own (G7), asked of the Projectile System so the AI keeps no copy (its callers call `Explosion.shields` directly, interface 3): from the burst a wall always stops the line, furniture
stops it when its `coverage` is above the body's height (the standing and crouched heights the character reports, `movement.posture_coverage`, read each `observe` by `learn_body` into `stand_height()` / `crouch_height()`; 60 and 35, `docs/cover-and-stance.md`), characters stop
nothing. `in_zone(space, threat: GrenadeThreat, p, height, exclude)` (the threat's `kind`, `radius` and `burst`): within `_zone_radius` (a frag's blast radius + `evade_margin`, a stun's flash radius) and not shielded.
`escape(space, map, threat: GrenadeThreat, runner: GrenadeRunner, exclude)` (`GrenadeThreat`, `ai/perception/grenade_threat.gd`: the
grenade's `kind`, `radius`, `burst` and `fuse_left`; `GrenadeRunner`, `ai/perception/grenade_runner.gd`: the NPC's `from` and `speed`) returns `{ spot, crouch, route }`: candidates are the circle just outside the zone (`zone + OUTSIDE_SLACK` 30 px), the shadows behind what the rays from the burst
meet (the first stopper for a crouched and for a standing body, `Explosion.first_stop`, 32 and 72 px behind it) and rings round the NPC; each is snapped onto the navmesh (`NavBuilder.snap`, dropped
if pulled more than 40 px), judged (outside the zone, or shielded standing = out of line, or shielded only crouched = `crouch`), **every** survivor is routed
(many candidates are the same point, the standing and crouching probes meeting the same wall: each point is snapped, each spot judged and each
route measured once, `tests/ai/grenade/escape_spot_matches_plain_test.gd` pinning the answer to the plain loop)
(`NavBuilder.route`; a straight line says nothing, a spot just behind a wall can be a house away) and the shortest route within `(fuse_left - 0.4 s) x run speed`
(`RUN_RELIABILITY` 0.85 of `movement.run_speed()`, or `movement.walk_speed()` once stamina is below `RUN_STAMINA`: both slowed by a
stun or a heavy outfit; `tests/ai/grenade/throw_timing_counts_slowed_walk_test.gd`) wins; `spot` is `Vector2.INF` when none is in time. Cost: ~150 snaps, ~300 rays and ~100 routes, only when a plan is
made; in the grenade match guard a plan made alone costs about 2.5 ms of burst work (the candidates round the burst, their snaps, the verdicts) and 1.2 ms of routes.
`can_lob(space, at, to, max_range, exclude)` is the throw test of the GRENADE tactic, the shots' group, the throw's re-check and the bang (within range, and `throw_clear`: the lob from
where the grenade leaves the thrower's hand, `_release_point` (the thrower's hand as it faces the spot, `Character.inventory.throw_release_offset`: the `throw` stance's hand, 6 px behind and 15 px right of it, learned with the grenades carried in `learn_carried` (the centre until one is), held
off a wall like the character's own hand), and the band `LOB_MARGIN` 8 px either side of that line the whole way (parallel edges, not converging on the spot: a jamb far along is met with the grenade's full width), each with nothing taller than `LOB_CLEARANCE` 50 px, the release height, on the line: a centre line
that grazes a jamb is a grenade that strikes it). `reach_of(kind)` is the range less `REACH_SLACK` 15 px: how far from its spot a thrower lets go, and the reach a throw spot is chosen in.
`throw_clear_on_arrival(space, at, to, exclude)` is `throw_clear` from `at` and from `ARRIVAL_SLACK` (6 px, the walk's own arrival) off it in the four axis directions: the test for a
spot the thrower walks to (a throw spot's `lob` callable; the bang's spot, through `AgentPerception.grenades.can_lob(..., walked = true)`).

**Shared on a physics frame (`_shared_burst`, `_shared_snaps`).** What depends on the burst alone is the same for every NPC fleeing it, and an evade
wave is 4 to 8 NPCs planning on one frame: `escape` keeps the candidates round the burst (`_around`: the circle and the shadows, ~50 rays), each spot's
verdict (keyed `[space, burst, kind, out_r, cover_reach, stand height, crouch height, the excluded rids' ids sorted]`, so a grenade that moved or an NPC
with other heights or margin has its own entry) and each candidate's navmesh spot (per map) in static dictionaries for the physics frame
(`Engine.get_physics_frames()`, cleared when a new one begins). Inside a physics frame the space and the map hold still for these queries (furniture
moves in the step, a dented collider is rebuilt deferred, the map syncs after the frame's callbacks, the characters are excluded), so what is shared is
what each NPC would work out; outside one (`Engine.is_in_physics_frame()` false) nothing is kept. Only `[from]`, the ring round it (`_ring`) and the
routes are the NPC's own. `escape` builds its list with `_candidates(from, around)` (`[from] + around + _ring(from)`), which the test probe's plain search (`tests/_ai/grenade_ai_probe.gd`) compares against too; the zone's edge with its slack is `_out_radius(threat)`. On the grenade match's evade waves
the worst wave measured (8 NPCs planning on one frame) went from 35.9 ms of planning to 17.4 ms (`docs/leadership.md`, Performance). Tests:
`tests/ai/grenade/escape_spot_matches_plain_test.gd` (120 escapes on one frame, many bursts) and
`tests/ai/grenade/evade_wave_spots_match_own_plan_test.gd` (five defenders plan together; each plan's spot equals the plain search's for that NPC on
that frame).

**Cover from a flash.** For a stun (`AgentThrow.cover_reach(kind)`, the `flash_cover_reach` of the stun's stats, 30 px, learned off the grenade: below) a piece of furniture shields a body from the burst only when the body is within that many px of it
(`Explosion.shields(space, burst, p, cover: CoverRule)`, its `cover_reach`); a wall always does; a frag's blast keeps the plain rule. `escape` also tries a spot right against the far face of each stopper near the burst (`FAR_PROBE`, `FAR_STEP`).

**Its own grenade (`_note_own`).** A grenade the NPC threw is known at once, and until a bounce marks it landed its spot is where it was aimed (`Character.weapon.aim_target()` from the hand, no further than that kind's throw range, `AgentThrow.range_of`), not the hand
it just left, so the zone it is in is the one the burst will have. **Replanning** is counted in `GameClock` frames (`REPLAN_EVERY` s of game time), not wall-clock ms: a fast headless run outruns the wall clock, and it runs on through a pause.
`AgentThrow.escape` takes the NPC's own position as the first candidate (already behind cover that shields a crouched body, it need not move).

**What it knows of a grenade it carries (`AgentThrow`).** No copy of the tuning: `learn(stats)` takes in what a grenade tells (`{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`, interface 6/7) from `Character.inventory.throw_stats(slot)` of every grenade the NPC carries (`learn_carried()`, every `observe`) and from each live grenade it notes (`ThrownGrenade.throw_stats()`, in `agent_grenades.gd`), and keeps it by kind, so it outlives the last grenade thrown. `range_of(kind)`, `radius_of(kind)`, `fuse_of(kind)`, `max_blind_of(kind)` and `cover_reach(kind)` answer from it (0 / 0 / 0 / 0 / INF for a kind never met; the flash a hostile is taken to be blind for is `FLASH_SHARE` 0.8 of `max_blind_of(&"stun")`); the perception's `grenades` part's `can_lob(at, to, kind)` (range and `throw_clear`), `throw_clear(at, to)` (the lob alone, from the hand), `reach(kind)` and `fuse(kind)` wrap them for the behaviour sub-domain; beside them its static `carried(character)` (`PerceptionGrenades.carried`: the kinds with a count, a frag
first, via `Character.inventory.item_count` of `AgentThrow.SLOTS`, `ItemRegistry.FRAG_SLOT / STUN_SLOT`). `AgentThrow` is also the geometry the snapshot's `SnapshotThrows.grenade_group` uses (`can_lob`, `in_zone`, `escape`, `run_speed`).

**The plan (`evade_plan()`).** For the known grenade that goes off first among those the NPC is in the zone of (or is already running from): `{ id, point, kind, radius, spot,
crouch, fuse_left, landed, lies }` (`landed` whether it has come down, `lies` where it is known to be now; `point` is where it was when the plan was made: a frag entry's stack
reads both, `Entry.expects_burst`, `docs/leadership.md` LD14). Made when the NPC is first inside a zone, made again when the grenade has moved 48 px (in flight, a bounce), or any distance that leaves the spot in its line
(`_still_safe`: a grenade rolling on a few px by a doorway; test `ai/grenade/evade_replans_when_spot_in_line`), at most every 0.15 s, and kept while the
grenade lives, so the NPC holds the spot until the burst. A grenade in flight is reacted to from where it is; the callout waits until it has come down (`announcements()`, the
spot it LANDED, which the allies' plans need) and is repeated once if it rests 30 px or more from there; an ally's call or the NPC's own throw is not radioed again.
The behaviour carries the plan out (`domain-ai-behavior`, "The evade reflex").

**Wrappers for the behaviour sub-domain on the perception's `grenades` part (`perception_grenades.gd`):** `can_lob(at, to, kind, walked := false)`, `throw_clear(at, to)`,
`reach(kind)` and `fuse(kind)` (above), `in_zone(kind, burst, p)` (a standing body at `p` inside the zone of a `kind` bursting at `burst`,
`AgentThrow.in_zone`, every character's body excluded: the frag entry's slot check, `docs/leadership.md` D16), and `evade_plan()`, `known()`,
`announcements()`. Tests: `tests/ai/grenade/`.
