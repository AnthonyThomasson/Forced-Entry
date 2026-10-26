---
name: domain-ai-behavior
description: Deep implementation detail for the AI BEHAVIOUR sub-domain (scenes/ai/behavior/) — running the decision planner's leaf as one primitive (move / engage / melee / interact / hold / reload / entry / throw / defend / ambush / follow) and the System-Two state Von lacks: engagement + retargeting, territorial confinement, posture and run policy, commitment (when a running choice re-decides), the full-path debug label, and the locomotion layer (nav pathing, room queries, furniture bulldozing). The fighting itself is `domain-ai-combat` (combat.gd), room search by sight is `domain-ai-coverage` (search_coverage.gd), where it looks and when it takes the shot is `domain-ai-watch` (watch.gd) and the tactical entry through a doorway (entry.gd: stack, slice the pie, cross, corners, clear, rear security, over the team radio, and the entry guard) is `domain-ai-entry`. Use when editing scenes/ai/behavior/ (behavior.gd, locomotion.gd) or working on how a chosen option becomes movement, holding ground, commitment/dwell timers, or pathing. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Behaviour sub-domain (`scenes/ai/behavior/`)

The ACT half: it runs the LEAF the decision planner chose — one primitive with its params — as
concrete movement + actions, and holds the System-Two state Von (a stateless ranker) lacks. It never
chooses WHAT to do and applies no policy beyond its params. It reads the world only through the
perception sub-domain and drives the character only through its public controller contract
(`movement.move_input`/`movement.aim_point`/`movement.run_input`, `movement.set_posture`, `inventory.select_slot`, `weapon.shoot`, `weapon.melee`, `anatomy.leg_kick`, `ammo.reload`, `use.interact_with`,
`use.end_interaction`: interface 7).

Files:
- `behavior.gd` — the primitive executor (a `Node`); owns engagement + commitment state, posture / run policy and the read-outs.
- `combat.gd` — shots, kicks, punches, bursts, back-off, the peek-and-cover cycle (`RefCounted`; `domain-ai-combat`).
- `search_coverage.gd` — covering a room by sight (`RefCounted`; `domain-ai-coverage`).
- `watch.gd` + the watch stage of `behavior.gd` — where it looks and when it takes the shot, in every primitive (`RefCounted`; `domain-ai-watch`, spec `docs/gaze-and-fire.md`).
- `entry.gd` — a tactical entry through a doorway, as a team member or alone (`RefCounted`; `domain-ai-entry`, spec `docs/tactical-entry.md`).
- `locomotion.gd` — the pathing layer (a `Node` child of behaviour); owns the NavigationAgent2D and answers `room_key_at(p)` / `inside_house(p)`.

The controller calls `setup(perception, nav_agent)`
once to build its `Locomotion`, `SearchCoverage`, `Combat`, `Watch` and `Entry` modules, then `apply_config(tuning)`, which sets the behaviour's
own tunables and its modules' straight from the NPC's tuning topics (`NpcTuning`) — re-calling it each decision so a runtime retune takes effect. (A
field is declared where it is read: the behaviour keeps only those it reads itself, and only `Combat`, built alone by a unit test, keeps
defaults.) On its first `control()` the controller calls `bind(character)`: the
behaviour keeps the NPC's body and hands it to each module's own `bind`, so none of their functions takes the character.

## The primitives (a leaf = `{ path, labels, primitive, params }`)

| Primitive | Params | What it does | Done / re-decides |
|---|---|---|---|
| `move` | `point`, `aim` (travel / target / threat / point), `target_id`, `arrive_room`, `look_around` | Path to the point (or until ENTERING `arrive_room`), aiming as asked (a threat in sight takes the eyes and the gun: the watch stage, below). Stops on arrival (`movement.move_input` is zeroed every tick after it, so the NPC stands still while the next decision is on its way: a real Von answer takes a moment, and from a point near the front door the last heading is out of the house; tests `tests/ai/movement/move_stops_on_arrival_test.gd`, `gaze_arrival_stops`). A `look_around` move (search / explore) walks all the way INTO the room, then **covers it by sight** (`search_coverage.gd`, the `domain-ai-coverage` skill) until it has SEEN the room or its budget runs out. ADVANCE is a `move` with `aim: target`: it closes in, then re-decides how to fight. | On arrival (forces a decision) — a `look_around` move only once the room is covered or its budget runs out (`max_commit_time` still caps the walk INTO the room before coverage starts). |
| `engage` | `point` (anchor), `target_id`, `style` (peek_cover / ambush), `confine_inside` | Path to the anchor firing at will, then fight from it: **peek-and-cover** (peek to the nearest spot with a clear shot, fire on `fire_cooldown`, duck to cover for `cover_time`, positions committed for `reposition_interval`) or **ambush** (hold the covered spot, fire the moment a line opens). ENGAGE and FLANK use this, anchored at the chosen spot or side. | Moving: at `max_commit_time`. In position: every `tactic_interval` (timer starts on arrival) or when `engaged` lapses. |
| `melee` | `target_id`, `confine_inside` | Close to `punch_range` and strike (a kick with a gun in hand, else a punch). | `tactic_interval` / `engaged` lapse. |
| `interact` | `object`, `id` | Walk to the object, face it, run the interaction, hold it `interaction_dwell`. | Dwell over (forces a decision), or approach cap. |
| `reload` | — | Equip the gun (`inventory.gun_slot()`), stand still (its eyes where the watch stage puts them) and `Character.ammo.reload()`; ends when the reload does (or at once if it can't start). | The reload ending (forces a decision), or `max_commit_time`. |
| `entry` | `opening`, `into`, `slot`, `side` (from the ENTER option) | A tactical entry through the doorway (`entry.gd`, `domain-ai-entry`): approach and stack, slice the pie, cross, take a corner, clear the room, maybe hold the door. Shoots a threat in sight in every phase (the watch stage). | When the entry is over (room clear, rear watch done, or given up); never on the cadence. The entry guard (below) also runs it, as a detour in the middle of another order. |
| `throw` | `point` (the spot), `kind` (`frag` / `stun`), `radius`, `slot`, `target_id`, `from` (where it throws from), `walk` (`from` is a throw spot) | The GRENADE tactic (`docs/grenades.md` G17; `combat.gd` does the throwing, `domain-ai-combat`): with a throw spot (issue #51 R13) walk all the way to it first (gun in hand, the watch stage on any threat; status "walking to the throw spot"; a held walk re-decides like a move; the walk is guarded like an engage's: `_entry_guard`, `_guards` and `_keeps_out_of_views` take the throw's `walk` stage, and `_resume_order` re-begins the throw (`_begin_throw_order`) when a detour's entry hands it back), then take the grenade in hand, turn to the spot (closing the last px if it drifted out of range since the offer), throw (the line is re-checked until the wind-up begins and the throw dropped if it is blocked; from the wind-up on it is committed), radio `frag_out` / `bang_out` as it leaves the hand (`take_throw_calls`), gun back in hand, then stand out the fuse (the watch stage shoots from there). An evade plan (the thrower in its own burst's zone) replaces the order at the release tick; `poll_throw` runs before it so the call is radioed first. Committed (no re-decision) during the wind-up. The order keeps its spot when the contact it was offered on ages out on the way, its pause behind a detour included: `salient_key()` keeps that hostile (`_throw_target`) while the perception still holds it as lost (`lost_hostiles()`, which drops the dead), so the lapse forces no decision; a target that died leaves the key and re-decides, and `update_known` ends a throw not yet in its wind-up whose target is neither a contact nor lost (`_throw_target_gone`), so nothing is thrown onto a body while that decision is on its way (`ai/grenade/grenade_throw_target_killed_redecides`). | When the grenade has gone off (or the throw could not be made, or the fuse plus a second ran out). |
| `defend` | `room`, `spot`, `door`, `door_pos`, `order_id` (the ORDER node's option, `docs/leadership.md` LD8) | Walk to the defend `spot` (`DEFEND_REACH` 8 px; a guarded walk where the entry guard applies: the guard, `_keeps_out_of_views` and `_guards` take it while it walks), then stand there, the watch stage keeping the gun on `door_pos` (`Watch.ease_gaze`) or, with none (a lone member of a room with several doorways), turning among the room's doorways, and on a threat in sight; pushed more than `DEFEND_DRIFT` 24 px off the spot it walks back. Crouches at its post in a fight like a hold. Says `in_position` (`take_order_steps`) on arrival. | Walking: at `max_commit_time`. At its post: only when `engaged` is fresh (its own shots at a hostile in its sector: the fight is the decision's, in the room) or a forced decision. |
| `ambush` | `opening`, `room`, `spot`, `door_pos`, `order_id` (the ORDER node's option, `docs/leadership.md` LD15; the post from `AgentEntry.ambush_spot`) | The `defend` walk and hold (`_apply_defend`: a guarded walk, `_guards` / `_keeps_out_of_views` / `_way_blocked` / `_entry_guard` take it as they take `defend`; back to the post past `DEFEND_DRIFT`; it never runs once arrived) at its post, **crouched** once arrived (`_wanted_posture`), the watch stage keeping the gun on the threshold, `door_pos` (`_resting` is `_arrived`). Status "on the way to its post" / "waiting in ambush". Says `in_position` on arrival. | Only when its order is no longer the live one (`_order_live()`: first contact ends it done, D18, `AgentPerception._end_ambush_on_contact`; a cancel or a new order), or, walking, at `max_commit_time`; never on the cadence. |
| `follow` | — (the FOLLOW leaf, `docs/leadership.md` LD20 to LD22) | Keep to the spot the squad gives it (`squad.follow_spot(character)`, read each tick; `squad` from the controller's config): the walk is re-aimed (`_follow_to`) only once the spot has moved `follow_retarget` from where it is going, and is `_arrived` within `follow_arrive` (`Locomotion.reached`: the agent done, so also where the path ends short of a spot it cannot reach; a follower catching up (`_catching_up`) whose walk target lagged its live spot re-aims at that spot there instead, until it is within `follow_caught_up` of it; its walk over, its catch-up is over) or when a body seals its only way (`_way_blocked`); on the way it aims along its path (`_aim_move`, the watch stage shoots what it sees). At its spot it stands facing away from its leader (the leash centre the controller pushes, `Combat.leash_center`: no `squad.leader()` read), and once it has stood `follow_still_time` (`_follow_stood`) with no threat and not under fire tops up a magazine at or below `low_ammo_fraction` (`Combat.magazine_low`, `Combat.top_off`). Status "keeping up with its leader" / "by its leader". | Never on the cadence (`wants_decision` false; `ongoing`): only a forced decision, or its spot gone (`Vector2.INF`: it leads now or follows no more) resolves it as a hold. |
| `hold` | — | Stand; the watch stage looks at the threat (and shoots it) or turns among the room's doorways. | Decide cadence. |

**Gaze and fire** are a policy too, the **watch stage** (`Behavior._apply_watch`, `watch.gd`; the `domain-ai-watch` skill, spec `docs/gaze-and-fire.md`):
after the primitive steers, a threat in sight (or one seen a moment ago with a clear line) takes the NPC's eyes and gun whatever the primitive
is (a move, a hold, a reload, an engage still walking, a throw once the grenade is away, any entry phase but `bang`; not a melee, an
arrived engage, an interaction, a throw still taking the grenade in hand and throwing it, or an entry's `bang`); no primitive
or entry phase has its own fire call. With no threat a walker looks down its path (`Watch.travel_point`) and a resting NPC (hold / reload /
an arrived move) turns among its room's doorways. An arrived move zeroes `movement.move_input`. Tests: `tests/ai/gaze/`,
`entry_guard_fires_from_outside`, `fire_dry_gun_on_move_reloads`, `engaged_retargets_to_visible`.

**Territory** is a param, not a policy: with `confine_inside` (set by the planner for a territorial
NPC's combat leaves) and a contact last seen outside, `Behavior` sets `hold_ground`, which `Combat` honours (see `domain-ai-combat`). With
`confine_room` (a member ordered to defend that room, LD8) `_keeps_in` sets it against a contact outside that room, and `Combat.peek_cover`
keeps its spots inside the room. **The leash** (a squad follower, `docs/leadership.md` LD23): the controller calls `set_leash(center, radius)`
every tick (its leader's live position and `Squad.leash`; `Vector2.INF` when it does not follow or holds an order, LD23), which `Behavior` hands to `Combat`
(`leash_center`, `leash`, `domain-ai-combat`); `walk_pending()` (a `move` or `engage` not yet arrived, a `throw` in its `walk` stage) is what
the controller's leash break reads, beside `in_combat()` and `committed()`.

**Orders (`docs/leadership.md`).** A leaf carrying `order_id` (the ORDER node's) says `moving` when it is adopted and the `defend` or `ambush` primitive
`in_position` on arrival (a held stack's member says it while `Entry.holding_for_go()`, LD13); `take_order_steps()` hands them (`{ order_id, step }`, each once until the next step differs) to the controller to
radio (LD7). `debug_state()["order"]` is the order leaf being carried out (`{ path, primitive, params, paused }`; while an entry detour pauses
it, `paused` and the order's own primitive and params, the running ones staying in `primitive` / `params`), {} with none. After an evade
(D8) the forced decision takes the order up again and the member walks back to its spot. **An order stops a walk, not a fight (LD6).** From the
frame an order is taken (`await_order(true)`, called by the controller with `_order_from`) until the decision made knowing it lands
(`set_leaf`, or `fallback`, clears `_awaiting_order`), `apply` zeroes `movement.move_input` after the primitive steers while `_walking()` and not
`committed()`: a `move` not chosen under COMBAT (`in_combat()` false: a search's, an investigation's, an idle walk), an `entry` in
`approach`, a `defend` / `ambush` not yet `_arrived`, a `throw` in its `walk` stage, an `interact` still walking to its object stand as an
arrived move does. A fight goes on (an `engage` arrived or on its way, `melee`, `reload`, `hold`, and a `move` chosen under COMBAT: an
advance, a retreat, a locate, whose path starts at `combat`),
and so does the rest of an entry (pie, crossing, corner, clear, cover, rear: stopped there it would stand in the doorway's funnel); an evade
or a committed step is never touched. The watch stage still looks and shoots. Tests `ai/decision/order_stops_walk`,
`order_fight_goes_on`, `order_retreat_goes_on`. An ordered stack (LD9) is an `entry` leaf with the
order's params: before its claim goes out `_apply_entry` sets `Entry.held_back` and `_detour_first(delta)` reads the whole way to the slot
(`Entry.approach_points()`, each leg on `AgentPerception.walk_route(p, "<opening>><into>", from)`; standing up to `ROUTE_WAIT` 2 s, `_route_wait`,
while that map is `pending`) for a threshold into a room not cleared and, unless another recipient is coming (`_entry_recipients_coming`), a doorway
view it passes: either is a detour first (`_entry.reset()`, `_begin_detour`), no claim made; else the entry begins afresh and claims. The
same `ROUTE_WAIT` covers the doorway's slots not laid yet (`Entry.laid(params)` false: the nav map not baked). On the walk its guard is
`_guard_approach` (thresholds as well as views, whatever `entry_enabled` says; `_ordered_stack()` sets
the perception's `ordered_walk` each tick, D4 / D11), the controller's `squad` reaches `Entry.squad` through `Behavior.apply_config(tuning, squad)`, with
`tuning.entry.order_ready_cap`, and the same order decided again leaves the running entry alone (`_same_order`). A leaf whose params carry `refused` (the
dead-end `hold_<opening>`, LD9 D21) says `refused` instead of `moving`. The rest is `domain-ai-entry`. **A join** (an entry leaf with
`join: true`, the squad's rally, LD24) (`StackClaim.is_join(params)`) keeps its `order_id` in the params, so `_same_order`, `_order_live` and the `moving` radio treat it as
the member's order, but it is no ordered stack: `_ordered_entry(params)` (an `order_id` and no `join`) is what gates `_ordered_stack()`
(D4's guarded walk, `ordered_walk`), the held-back way reading (`held_back` / `_detour_first`) and `_guard_approach`'s ordered branch. A
join whose entry cannot `begin` (no slot at a dead end) is ended `refused` (`AgentPerception.end_order`), so the member follows. LD25
and D26: `_join_over()` is true once for a running join whose order is no longer live while the entry is in `approach` or `stack`, and
`_apply_entry` then sets `_resolved` ("join over", `_join_done` reset in `_adopt`), so the member decides at once (FOLLOW); later phases run
the entry to its end. A frag
entry's thrower (LD14) radios `frag_out` through the same `take_throw_calls` as a GRENADE throw: `poll_throw` takes `Entry.take_thrown()`
while the primitive is `entry`.

**Running** is a behaviour policy, not a primitive: after the primitive steers and the watch stage has picked its threat, `_should_run()` sets
`character.movement.run_input` only while TRAVELLING (a `move` or `engage` not yet arrived — never a `look_around`
search, ambush/peek, interaction, hold or tactical entry — or a `melee` closing in), when the leaf carries `run: true` or
the NPC is under fire, the destination is farther than `run_min_distance` (straight line), and a run can
start (`run_start_fraction` of the stamina bar, or already running). A `follow` not yet arrived runs once it is more than the squad's
`follow_step` from its live spot (whatever the leaf: a follower catches up with its file, LD21), and from then is catching up
(`_catching_up`, set when that run starts): it runs on each tick it steps until it is back within the squad's `follow_caught_up` of
its live spot, or its walk is over short of it. A tick with no step (a give-way, a `keep_off` stop, a held walk) keeps the
catch-up, and the next step runs without asking `run_start_fraction` again; a gate that drops the run (a shot to take, a reload due,
the stamina run dry) ends it, as does another primitive. The Character spends the stamina and walks once dry. Tunables (the
NPC's `tuning.pace`): `run_enabled`, `run_min_distance`, `run_start_fraction`.
`debug_status()` reads "running" / "running into position" while it sprints; `debug_state()` has `running`.
A running NPC cannot shoot or reload (`Character.weapon.shoot()` is ignored while running), so `_should_run` is false while a shot is available
(`Combat.can_fire_at(threat)`: loaded, in range, clear line) or the reload reflex is due (`Combat.reload_due`): it drops to a walk and
takes the shot instead of sprinting on past its range. A leaf with `run_through_fire` (the RETREAT node) keeps sprinting. `Combat.shoot()`
still skips a shot while `movement.is_running()` without spending the fire cooldown.
Tests: `tests/ai/movement/ai_runs_to_destination_test.gd`, `retreat_keeps_running_test.gd`.

**Posture** is a behaviour policy too (spec: `docs/cover-and-stance.md`, A1 to A3): after the primitive has steered and `movement.run_input` is set,
`_apply_posture` writes the posture `_wanted_posture` asks for through `Character.movement.set_posture` (idempotent, so every tick). Everything outside a
fight and everything travelling to a destination (`move`, an `engage` not yet arrived, `melee`, `interact`) **stands** — only a standing body runs —
and so does an NPC that is running. Fighting in place (`engage` arrived, or `hold` / `reload` with a hostile known or shots landing) it **crouches** (behind cover, in the open or
pinned alike, and when moving about inside the fight). Two orders crouch outside a fight: an `ambush` at its post (LD15), and a member of a
frag entry holding its slot for the burst (`Entry.holds_crouched()`, LD14). A crouch is held `posture_dwell` (0.7 s) before it is dropped; standing back up is never delayed.
Tunables (the NPC's `tuning.pace`): `posture_enabled` (the `ai.posture` switch), `posture_dwell`. `debug_status()` appends "crouching";
`debug_state()` has `posture`. Not a decision-tree level: Von is never asked, so it works with the server down. Tests:
`tests/ai/posture/posture_crouches_in_fight_test.gd`, `posture_pinned_crouch_test.gd`, `posture_stands_to_run_test.gd`.

**Combat** — the gunnery, the peek-and-cover cycle, bursts, backing off a blocked barrel, the reload reflex, melee and the
no-per-weapon-code rule — is `combat.gd`: the **`domain-ai-combat`** skill. `Behavior` passes it the engaged contact and `hold_ground`.

## The evade reflex (G16) and the blind NPC (G15)

**Evade (`Behavior.set_evade(plan)`, called every tick by the orchestrator with the perception's `evade_plan`; `docs/grenades.md` G16).** Outside Von and over every primitive, like the
auto-reload, but for the NPC's own throw in its wind-up (`throw_stage` `windup`: the grenade leaves the hand within 0.3 s toward its spot; the evade starts the tick it has, `poll_throw` running first; test `ai/grenade/evade_waits_for_own_windup`): while a live grenade threatens the NPC it is carried out instead of the running order, an entry (committed or not) and an interaction included. The first
tick of a plan drops the detour, abandons the entry (the stack is told), and replaces the order with `evade` (path `["evade"]`, labels `EVADE - a live frag grenade`);
no decision is started or adopted while it runs (the controller's `_should_decide` / `_on_decided`, `set_leaf`). An entry in its `bang` phase is left
to its own hold when `Entry.expects_burst(plan)` says the grenade is the bang's (a stun, or a frag whose burst leaves its slot out of the zone, LD14; `domain-ai-entry`). `_apply_evade` runs all the way into `plan.spot` (`Locomotion.move_to`
within `EVADE_REACH` 6 px: a spot is out of the burst's line with little room to spare, so a stride short of it can be in the line; looking where it
goes, running when `run_enabled` and stamina allow), then holds it facing away from the grenade, **crouched when the spot is cover** (`plan.crouch`); the watch stage does not run (no
turning to a threat, no shot). With no spot in time it stays, facing away (a stun then blinds it for the back-turned share only), crouched for a frag. When the plan ends (the burst) `_resolved` forces
a new decision. Read-outs: `evading()`, `evade_spot()` (the controller's `debug_grenades().escape`), `debug_state()["evade"]`. Tests: `tests/ai/grenade/evade_*`.

**A blinded NPC** (`Character.stun.is_blind()`): the orchestrator starts no new decision (`_should_decide`) and re-decides the tick its sight returns; the order it was carrying out goes on
(it stumbles: the character is slowed and drifts); the perception keeps its contacts (so the watch stage's engaged-contact pick, or the arrived peek-and-cover, fires at the hostile's last-known
spot with the character's aim sway, G13) and sees no new one. Whether it fires blind is the orchestrator's one roll as it goes blind (from not blind),
`_rng.randf() < tuning.grenades.blind_fire_chance` (1 always fires; 0.5; `_rng` the controller's own `RandomNumberGenerator`, seeded once at bind from
`hash("<character name> <spawn position rounded>")`, each blinding taking the next draw; a re-stun while blind draws nothing), handed in by
`set_blind_fire(on)` to `Combat.blind_fire`; on a miss `Combat.holds_fire()` (blind and no blind fire) refuses `Combat.shoot()` (no round, no dry click)
and cuts `continue_burst`, so every fire path (the watch stage's `fire_at_will`, the peek, the ambush) holds until it can see; the aim still turns to the
spot. `debug_state()["holds_fire"]` reads it. Tests: `ai/grenade/stunned_defender_blind` (chance 1), `stunned_defender_holds_fire` (chance 0). A deafened NPC hears no gunfire, no hit elsewhere and no callout (the orchestrator drops them).

## Tactical entry (`entry.gd`) — `domain-ai-entry`

The entry phase machine, its team radio, the entry guard's detours and the entry read-outs are the **`domain-ai-entry`** skill.

## Public interface (what the orchestrator calls)

- `setup(perception, nav_agent)` (build the Locomotion, coverage, combat, watch and entry modules), `apply_config(tuning, npc_squad := null)` (set its own tunables
  and its modules' from the NPC's `NpcTuning` topics, and the squad; re-callable each decision), `bind(character)` (the body, once); config fields; `rooms` (set each tick; forwarded to Locomotion).
- `set_leaf(leaf)` — adopt: snap the point onto the navmesh, capture the target (a fight whose target
  is no longer known drops to hold and forces a re-decision), commit.
- `update_known(known, delta) -> bool` — adopt the perception's hostiles; retarget a lost engaged
  contact to the nearest other; with none left, a leaf that needs a target ends → true (re-decide); a throw not yet in its wind-up
  whose target is dead or forgotten ends too.
- `salient_key()` (the known-hostile ids and the engaged contact's inside state; a running throw order keeps its hostile in it after the contact ages out, not once it is dead, G17), `service_interaction(delta, force)`, `take_resolved()` (with `resolve_reason()`, read just before it:
  "way blocked" when a body seals the only way of the walk and stays, "" for a finished task; the controller forces its decision with it),
  `wants_decision(decide_timer_elapsed)` (the table's last column), `apply(delta)`,
  `fallback()` (steady hold when no decision can be had), `committed()` (crossing a doorway, throwing the bang, a throw's wind-up: no decision may
  start), `take_entry_calls()` (entry steps for the controller to radio), `debug_entry()`, `debug_entry_view()`,
  `debug_combat()`, `debug_coverage()`, `debug_progress()`, `path_label()`, `throw_plan()` (the throw about to be made,
  `{ from, to, kind, radius }`, `{}` once the grenade is away: the grenades overlay's `throw`), `order()` (the running order's `{ path, labels }`),
  `take_entry_turned()` and `adopt_bang(path, labels)` (an ENTER that turned into a bang one is re-adopted as STUN ENTRY, E17: `domain-ai-entry`),
  `take_order_steps()` (the order progress to radio, above), `await_order(on)` (a walk the order replaces stands until its decision lands, above).
- `reached_lead()` — the investigation lead (`params.lead`) the running move has reached, which the
  controller hands to perception's `check_lead()` so it isn't offered again.
- `ongoing()` — the running choice is still in progress (en route, fighting, using an object): only
  then does the planner mark the option continuing it "(your current plan)" — a finished move must
  not be re-picked just because it was the last plan.
- Read-only: `current_act()` (path ids), `in_combat()`, `debug_status()`
  — **the full decision path, every level, joined with " - "** (`COMBAT - Intruder - FLANK - their
  left side (kitchen)  · in position, looking for a shot  ⚠ under fire`), `activity_text()` (the same
  path + progress + how long, for Von's "current activity" line), `debug_state()` (JSON-safe).

## Locomotion (`locomotion.gd`)

All movement flows through `move_to(dest, within := 0)` on a `NavigationAgent2D` (`within`: arrive closer than the agent's
own 16 px; the entry's stack slots use `StackClaim.SLOT_REACH` 6 px, since a member a stride short of its slot stands on the next one). `path_ahead()` returns the walk it was just given
(`{ path, index }`, or {}), which the behaviour's entry guard reads. The Navigation
domain bakes furniture in as navmesh holes and rings the house with a walkable outdoor strip.
Steering always aims at `get_next_path_position()` — a navmesh waypoint, so it is wall-safe, and for
an unreachable target it steps toward the closest reachable point. Furniture physically on the route
(a piece shoved off its baked hole) is bulldozed by the character's own push physics; there is no RVO
avoidance and no straight-at-the-destination fallback. `reachable(p)` snaps a point onto the navmesh
(every leaf destination goes through it); `reached(point, within := 0)` reports arrival (at the free spot it took, below; never while held).
Falls back to straight-line steering with no agent. It also holds the house `rooms` (set by `Behavior`) and answers `room_key_at(p)` /
`inside_house(p)` for the move's `arrive_room` test and the coverage and combat modules. `reachable` / `on_navmesh` always use the plain map.

**Characters (issue #53).** A walk accounts for the characters the NPC KNOWS of and never walks into one: `Behavior` hands it
the perception's contacts every tick (`bodies`, set in `Behavior.apply`: what it sees, or saw within `contact_memory_ttl`, with `pos`, `vel`, `facing`, `visible`);
a body it has not seen does not exist for the walk, and one out of sight whose last spot (within `WALK_BODY_RANGE`, 450 px) it can see
now with nobody on it has moved on (`Behavior._walk_bodies`, via `AgentPerception.visible_points`). `ignore_id` leaves out the one a
`melee` closes on. A body whose track is slower than
`REST_SPEED` (40 px/s) is at rest, any faster one a walker. Each walk (a new one when the destination moves more than `NEW_WALK` px) is in
one of four ways, checked once a physics frame (`_check`):
- **plain**: the world's own map (furniture only). The first known body at rest the path passes closer than `PASS_CLEARANCE` (32 px, and
  closer than the NPC stands to it now) within `LOOKAHEAD` (400 px), or one standing on the goal, ends it:
- **doors**: the Navigation domain's avoid map (`NavBuilder.avoid_map`: the planning bake with the doorway views carved out, E18), for a walk
  `Behavior` marks `avoid_doors` (above; `avoid_entering` = `"<opening>><into>"` while the primitive is an `entry`, so its approach keeps out of the
  room it goes into and its own doorway's view, cleared or not). `_update_doors` asks the perception for the route (`walk_route(goal, avoid_entering)`) each frame until
  it is decided (plain while the avoid map bakes: `pending`), then every `DOORS_RECHECK` (2 s) while round the views (which keeps the map alive and follows
  the rooms as their clear lapses): the avoid map when the plain route comes into a view and the route round them is within `door_avoid_ratio` x plain +
  `door_avoid_slack`, else plain (and `passing_ahead` secures what it crosses). A walk that is not guarded (`avoid_doors` false) drops it. A body at rest on
  a doors walk's path takes it to the steering map (round) or holds it as on a plain one: the steering map has no views carved, so E15 secures what that
  crosses; once the way is free it goes back to the avoid map: a held walk at once (`_free_way`), a walk gone round once the avoid map's route to the goal passes
  no known body at rest all the way, not only the first `LOOKAHEAD` (`_clear_on`, looked at every `RECHECK` s; a body just past the look-ahead would send it
  round again a few strides on). Once the avoid map's route is done short of the goal (a slot by a view's edge lies off that map) the last
  stretch is walked plain (`_last_stretch`; the walk is decided plain for the rest). Tests: `tests/ai/movement/npc_doors_walk_round_body`, `npc_doors_walk_body_on_goal` (scripted).
- **round**: the Navigation domain's steering map, with every character at rest carved out, when its route reaches the goal (or ends within
  `LAST_LEG`, 64 px, of it with the plain way on passing no known body at rest: a stack slot between two taken ones lies inside their carved
  margins) and passes no known body at rest (`_goes_round`), whatever the detour (out of the room and in by another door included). A round
  walk done short of a goal no body stands on walks the rest plain (`_last_stretch`, `_last_leg`), held short of a body on it; held, it
  looks again every `RECHECK` s for a way round: a route that ends at the goal, or a new last leg whose plain way passes clear of every known
  body at rest (`_goes_round(..., held_leg)`, `_resting(goal, INF)`), so it never takes one the body holding it, or another, stands on and
  cannot flip between two holders (test `ai/entry/entry_last_leg_sealed_goes_round`);
- **held**: no way round (the body seals the only way, or has just stopped and the map, re-baked every 0.75 s, has not carved it yet),
  or the body stands on the goal: the NPC walks on until `STOP_GAP` (56 px) from the body and stands. It looks for a way round every
  `RECHECK` s and walks on the moment nothing known is in the way. After `WAIT` (0.75 s), and every `REPLAN_EVERY` (4 s) after, it
  re-plans (on its standing time: a hold that begins again within `HOLD_GAP` 0.5 s of game time (`GameClock`: a pause is no gap; test
  `ai/movement/npc_hold_clock_across_pause`) of the last ending, the NPC within `HOLD_MOVED` 16 px of
  where that one began, is the same hold and keeps its clocks, `_begin_hold`, so a walk aimed again, a free spot tried or a body read as
  moving for a frame does not start the wait over), once the steering map shows the body it is held by (`_carved`: its centre more than `CARVED_GAP` 16 px off that map) or
  `CARVE_WAIT` (2 s) past the re-plan time whatever the map shows: a body on the goal sends it to the nearest free spot near the destination (`_free_spot`: rings from 44 px, open floor, 40 px
  clear of every body at rest, same side of the walls); any other hold raises `take_blocked()`, on which `Behavior._way_blocked`
  re-plans whatever walks: a `move` / `engage` / `melee` / `interact` (and a `throw` still closing on its spot) ends with `resolve_reason()`
  "way blocked" and the controller re-decides; an `entry` re-plans its own walk (`Entry.way_blocked`, `domain-ai-entry`). The walk
  stays held meanwhile; an evade holds the best spot it has until the burst. So a held walk first re-plans within `WAIT` +
  `CARVE_WAIT` s, and again at most `REPLAN_EVERY` + `CARVE_WAIT` s after each re-plan. A walk done at the free spot beside a taken destination goes on to the destination once nobody stands on it (`_begin`,
  as the caller asks again: `_check` does not run once a walk is over).
  The steering map is the one `NavBuilder.steering_map` names when `setup` runs (a match places its NPCs only once both maps are
  `NavBuilder.ready`, `domain-main`); `_goes_round` waits for `NavBuilder.ready` on both maps too.
**Giving way (`_give_way`)**: of two walkers in view whose
courses come within `GIVE_CLEARANCE` (36 px) in the next `GIVE_HORIZON` (1.2 s), or in the time the NPC's own walk still takes when
that is shorter (`_way_left`, along the agent's path to its end, at its pace: its course reckoned only to the end of its walk, so it never
gives way to a walker its walk stops short of, as a follower closing on its spot behind a leader walking on, LD21; near the end of its walk
that short look-ahead holds for every walker, `GIVE_IMMINENT`'s stop included), the one with the right of way walks on (`_has_way`: the
other sees it, by distance or its facing, and its instance id is the lower; one that cannot see it cannot give way, so the other does); the
other steps aside off the walker's line when it stands on it (open floor, clear of other bodies, never toward the walker), else waits, until
the walker has gone by (at most `GIVE_MAX` 3 s). Even with the right of way it stops for a walker on course closer than `GIVE_IMMINENT`
(50 px), whose track may not show it setting off yet. Last of all, whatever the walk (and the combat back-off), `keep_off` drops the part of a step that heads
into a known body closer than `KEEP_OFF` (36 px) so the NPC slides past it (the agent cuts a path's corners by up to its 16 px
`path_desired_distance`); with nothing left of the step it stands. `holding()` is true whenever the walk stands or steps aside for a body (held, giving way, kept off, or at the free spot beside a taken destination): the entry's crossing then does not push on straight. `held_by()` (the instance id of the known body a held walk stands short of, 0 when not held), `held_at()` (where that body stands, INF when not held) and `held_time()` (s held, 0 when not) are what
an entry asks before it gives its slot up for a hold (`Entry.way_blocked`, `domain-ai-entry`); `seals(p)` (the plain way from where the NPC
stands to `p` passes the body the walk is held by, closer than `PASS_CLEARANCE`) is what it asks of each waypoint left. `debug_state()["loco"]` adds `way`, `held_for`, `giving_way`, `last_leg`. Cost: per walker per
frame, the agent's path against the few known bodies near it; a steering route only on a change of way or every `RECHECK` while held; an
avoid-map route every `RECHECK` while a walk that keeps out of the doorway views is round a body, and `walk_route` every `DOORS_RECHECK`
while it is round the views; the free-spot search only on a re-plan. Tests: `tests/ai/movement/npc_detours_round_body_at_rest`, `npc_waits_at_doorway_held_by_teammate`,
`npc_dest_taken_stops_nearby`, `npc_routes_only_round_bodies_it_sees`, `npc_walkers_give_way`, `npc_give_way_walk_ends_short`, `npc_routes_around_character`,
`npc_own_hole_does_not_slow_it`, `npc_doors_walk_round_body`, `npc_doors_walk_body_on_goal`, and the scenario `tests/ai/entry/entry_team_no_bumping`
(real Von; `tests/_ai/bump_probe.gd` measures "walks into", and standing pressed against a body, which `keep_off` alone stops short of a bump).
