extends Node
## AI BEHAVIOUR sub-domain. Runs the LEAF the decision planner chose — one behaviour PRIMITIVE with
## its params — as concrete movement and actions on the character, and holds the System-Two state
## Von (a stateless single-shot ranker) lacks: the engaged contact, the peek-and-cover combat cycle,
## the interaction in progress, and the COMMITMENT that keeps a choice running until it completes or
## a re-decision is due. The primitives:
##   move     — go to `point` (or until entering `arrive_room`), aiming along the way (`aim`: travel
##              / target / threat / point); a `look_around` search move covers the room by sight
##              (`search_coverage.gd`): it turns and relocates until it has seen all of it.
##   engage   — go to `point`, then fight `target_id` from there: `peek_cover` (step out, shoot,
##              duck) or `ambush` (hold the covered spot, fire the moment a line opens).
##   melee    — close on `target_id` and punch.
##   interact — walk to `object`, run its interaction `id`, hold it for `interaction_dwell`.
##   reload   — stand and swap in a fresh magazine (`Character.ammo.reload()`), then re-decide.
##   entry    — go through doorway `opening` into room `into` as a team member or alone: stack,
##              slice the pie, cross without stopping, take a corner, clear the room (`entry.gd`).
##   throw    — walk to the throw spot `from` when it has one (`walk`), take a grenade in hand, aim
##              at `point`, throw it, radio it and wait out the fuse with the gun back in hand
##              (`combat.gd`; the GRENADE tactic, `docs/grenades.md` G17).
##   defend   — the order to defend `room` (`docs/leadership.md` LD8): walk to the defend `spot`,
##              then hold it with the gun on its doorway `door_pos` (or, with none, turning among
##              the room's doorways), as long as the order stands.
##   follow   — keep to the spot its squad gives it (`Squad.follow_spot`): walk there, stand there
##              facing away from its leader, top up a low magazine at rest (`docs/leadership.md`
##              LD20 to LD22).
##   hold     — stay and watch.
## Outside the primitives, **the evade reflex** (`set_evade`, `docs/grenades.md` G16) takes over the
## NPC whatever it is doing, an entry included, while a live grenade threatens it: it runs to the
## safe spot the perception found, crouches there if it is behind cover, holds facing away until the
## burst, and re-decides. Whatever the primitive, a final WATCH stage (`watch.gd`,
## `docs/gaze-and-fire.md`) puts a threat in sight under the NPC's eyes and gun and, with none,
## makes it look down its path or at its doors. It never chooses WHAT to do — the planner does — and
## applies no policy beyond the params it is handed (`confine_inside` keeps a territorial NPC from
## chasing out of the house). It owns a `Locomotion` child for all pathing, a `Combat` module
## (shots, punches, bursts, the peek-and-cover cycle) and a `SearchCoverage` module, reads the world
## only through the PERCEPTION sub-domain (known contacts, combat geometry, engagement memory) and
## drives the character only through its public controller contract (`move_input` / `aim_point`,
## `select_slot`, `shoot`, `melee`, `interact_with`, `end_interaction`). All tunables are set from
## the controller's exports by `apply_config(cfg)`.

const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")
const Combat := preload("res://scenes/ai/behavior/combat.gd")
const SearchCoverage := preload("res://scenes/ai/behavior/search_coverage.gd")
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const Watch := preload("res://scenes/ai/behavior/watch.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
## Seconds past a grenade's fuse that the thrower waits for the burst before it gives up waiting.
const THROW_WAIT_MARGIN := 1.0
## How near (px) a contact out of sight must have been last seen for a walk to check that it is
## still there (`_walk_bodies`).
const WALK_BODY_RANGE := 450.0
## How close (px) an evade walks into its safe spot: the spot is out of the burst's line with only a
## little room to spare either side of it, so a body that stops the agent's usual stride short of it
## can still be in the line (`AgentThrow`).
const EVADE_REACH := 6.0
## How close (px) a defender walks into its defend spot.
const DEFEND_REACH := 8.0
## How far (px) a defender at its post may be pushed off its defend spot before it walks back.
const DEFEND_DRIFT := 24.0
## How each phase of a tactical entry reads in the status line.
const ENTRY_PROGRESS := {
	"approach": "heading for the door", "stack": "stacked at the door", "pie": "slicing the pie",
	"bang": "throwing a stun in", "cross": "going in", "corner": "taking a corner",
	"clear": "clearing the room", "cover": "covering the doors on", "rear": "holding the door",
}
## How far (px of walking) the entry debug view looks ahead along the walk for the next uncleared
## doorway.
const GUARD_PREVIEW_RANGE := 2000.0
## The longest (s) an entry waits for the nav map its doorway's slots are laid on (`Entry.laid`),
## and the read of an ordered entry's way (`_detour_first`) for the map round the doorway views, to
## be baked.
const ROUTE_WAIT := 2.0

# --- The tunables the behaviour reads itself, set by apply_config() from the controller's exports
# of the same name.
## Seconds an object interaction is held before it ends.
var interaction_dwell: float
## Safety cap (s) on a move or approach before it re-decides.
var max_commit_time: float
## Gaze turn speed (rad/s) while a searcher looks around a room it is covering, or a defender's gun
## turns to its doorway.
var search_look_rate: float
## Seconds a fight in position runs before it re-asks its tactic.
var tactic_interval: float
# Running: whether the NPC may sprint on the way to a destination (see `_should_run`).
## May sprint at all.
var run_enabled: bool
## Only run when farther than this (px) from the destination.
var run_min_distance: float
## Stamina needed to START a run (once running it goes on until dry).
var run_start_fraction: float
# Posture: whether the NPC may crouch in a fight (see `_wanted_posture`), and how long it keeps one
# before changing.
## May crouch at all.
var posture_enabled: bool
## Seconds a crouch is held before it is dropped.
var posture_dwell: float
## The entry guard: any walk into a room that is not cleared goes in by tactical entry
## (`_entry_guard`; `docs/tactical-entry.md` E9).
var entry_guard: bool
## Start the entry once the doorway is this near (px of walking).
var entry_guard_range: float
## Seconds a doorway whose entry was given up is left alone before the guard may start another.
var entry_guard_rearm: float
## Seconds a doorway secured in passing (E15) is left alone before the guard may secure it again.
var entry_secure_time: float
## A hostile out of sight keeps the NPC's eyes this long (s) while there is a clear line to where it
## was.
var watch_lost_gaze: float
## A magazine at or below this share of its capacity is low: a follower at rest tops it up.
var low_ammo_fraction: float
## The NPC's squad (`ai/team/squad.gd`), null without one: where a follower keeps to.
var squad: Node = null
## World-space room rects (`{ key, type, rect }`), set each tick by the controller from its
## composer's inject; handed on to the Locomotion child, which answers the room queries.
var rooms: Array = []:
	set(value):
		rooms = value
		if _loco != null:
			_loco.rooms = value
## The NPC's body, handed in once by `bind`: what every primitive drives.
var _character: Node
## The perception sub-domain (contacts, combat geometry, engagement memory).
var _perception: Node
## The Locomotion child (pathing, rooms).
var _loco: Node
## Room coverage by sight for a search move; see search_coverage.gd.
var _coverage: RefCounted
## Shots, punches, bursts and the peek-and-cover cycle; see combat.gd.
var _combat: RefCounted
## A tactical entry through a doorway; see entry.gd.
var _entry: RefCounted
## The threat that takes the eyes and the doors a resting NPC watches; see watch.gd.
var _watch: RefCounted
## The contact holding the NPC's eyes and gun this tick ({} = none); see `_apply_watch`.
var _threat: Dictionary = {}
## What set the gaze this tick, for the read-outs: threat / doors / primitive.
var _gaze := "primitive"
## An ENTER leaf was adopted and its entry starts on the next tick (`_apply_entry`).
var _entry_pending := false
## How long (s) an ordered entry has waited, its claim held back, for the map round the views
## (`_detour_first`).
var _route_wait := 0.0
## The leaf an entry detour paused (see `_begin_detour`); {} when the entry is the NPC's own order.
var _resume := {}
## Seconds the guard has been watching (sim time), for the re-arm of a given-up doorway.
var _guard_clock := 0.0
## Doorway id -> `_guard_clock` before which the guard leaves it alone.
var _guard_off := {}
## Known hostile contacts this tick (nearest first), from perception.
var _hostiles: Array = []
## Every contact the perception handed in this tick (`update_known`), hostile or not.
var _known: Array = []
## The running primitive.
var _primitive: StringName = &"hold"
## Its params (from the leaf).
var _params := {}
## The decision path ids (e.g. ["combat", "t_12", "flank", "side_left"]).
var _path: Array = []
## The decision path as labels (e.g. ["COMBAT", "Intruder", "FLANK", "their left side (kitchen)"]).
var _labels: Array = []
## When the running leaf was adopted (game msec, `GameClock.msec()`).
var _leaf_ms := 0
## The leaf's destination, snapped onto the navmesh.
var _point := Vector2.ZERO
## A move that completes on ENTERING this room ("" = on reaching `_point`); ignored while looking
## around.
var _arrive_room := ""
## Whether the destination has been reached.
var _arrived := false
## Where a follower's walk is going: its follow spot as last re-aimed (`Vector2.INF`: not yet).
var _follow_to := Vector2.INF
## When (game s, `GameClock`) the follower last came to a stop at its spot.
var _follow_stood := 0.0
## A follower running to catch up (LD21): set when its follow run starts, it holds through a tick
## with no step (a give-way, a `keep_off` stop, a held walk) and is cleared once the follower is
## within `follow_caught_up` of its live spot or its walk is over short of it, when a gate drops
## the run (a shot to take, a reload due, its stamina dry) or when the primitive changes.
var _catching_up := false
## A search/explore move that covers the room by sight on arrival (vs resolving at once).
var _look_around := false
## Instance id of the contact being fought (0 = none).
var _engage_id := 0
## That contact's body (excluded from line-of-fire rays).
var _engage_node: Node2D
## That contact's last-KNOWN position (from memory).
var _engage_pos := Vector2.ZERO
## Whether that contact was last seen inside the house.
var _engage_inside := false
## The character was running last tick (for the status line).
var _running := false
## The character's posture last tick (for the status line and overlays).
var _posture: StringName = &"stand"
## Seconds before a crouch may be swapped for standing (no flicker).
var _posture_hold := 0.0
## The character was reloading last tick (for the status line and overlay).
var _reloading := false
## A `reload` leaf has seen its reload begin, so it ends when the reload does.
var _reload_started := false
## Combat: stay inside the house (territorial vs. an outsider).
var _hold_ground := false
## Seconds left before a fight re-asks which tactic to use.
var _tactic_timer := 0.0
## The object to approach + use (interact), else null.
var _target_obj: Node
## The interaction id to run on `_target_obj`.
var _interact_id := ""
## Delays an interaction one frame so facing settles first.
var _act_armed := false
## Committed to an active object interaction.
var _in_interaction := false
## Seconds left before ending the current interaction.
var _interaction_timer := 0.0
## Seconds left on the current move/approach commitment (safety cap).
var _commit_timer := 0.0
## A task just finished (arrived / interaction ended / target lost) → re-decide.
var _resolved := false
## Why `_resolved` was raised when it was not a finish ("way blocked"; see `resolve_reason`).
var _resolve_reason := ""
## A decision came back while the bang's thrower was committed to its throw: it is taken again once
## the stun is away.
var _held := false
## The running join's end has been said (`_join_over`, LD25).
var _join_done := false
## The plan to get clear of a live grenade being carried out ({} = none); see `set_evade`.
var _evade := {}
## The evade reached its safe spot.
var _evade_arrived := false
## The grenade being thrown (`throw` leaf): &"frag" / &"stun".
var _throw_kind: StringName = &""
## Where it is thrown to.
var _throw_spot := Vector2.ZERO
## Throws to radio since the last `take_throw_calls()`: { kind, point }.
var _throw_calls: Array = []
## Seconds left waiting out the grenade's fuse once it has left the hand (-1: not thrown yet).
var _throw_wait := -1.0
## The grenade thrown has been seen in the world (it is its own, always known): the wait ends when
## it is gone.
var _throw_seen := false
## Progress on the order being carried out, to radio since the last `take_order_steps()`: {
## order_id, step }.
var _order_steps: Array = []
## The last step said of an order (`{ id, step }`), so a step is said once until the next differs.
var _order_said := {}
## An order was just taken and its decision has not landed: a walk it replaces stops
## (`await_order`).
var _awaiting_order := false


## Build the Locomotion child and capture the perception sub-domain. The controller calls this once
## in its _ready(); it then hands itself to apply_config(), which sets the tunables (here and again
## each decision).
func setup(perception: Node, nav_agent: NavigationAgent2D) -> void:
	_perception = perception
	_loco = Locomotion.new()
	_loco.setup(nav_agent)
	_loco.rooms = rooms
	_loco.views = perception
	add_child(_loco)
	_coverage = SearchCoverage.new()
	_coverage.setup(_loco, perception)
	_combat = Combat.new()
	_combat.setup(_loco, perception)
	_combat.dry.connect(_on_dry)
	_watch = Watch.new()
	_watch.setup(_loco, perception)
	_entry = Entry.new()
	_entry.setup(_loco, perception, _coverage, _watch, _combat)


## Hand in the NPC's body, which the behaviour and its modules drive from then on. The controller
## calls this once it knows which character it drives.
func bind(character: Node) -> void:
	_character = character
	_loco.bind(character)
	_coverage.bind(character)
	_watch.bind(character)
	_combat.bind(character)
	_entry.bind(character)


## Set the behaviour's own tunables and its modules' (Locomotion, the watch, coverage, combat and
## entry modules) straight from `cfg`, the controller, whose exports of these names are the one
## authoring surface. Idempotent, so the controller may call it each decision to pick up an export
## retuned at runtime.
func apply_config(cfg: Node) -> void:
	interaction_dwell = cfg.interaction_dwell
	max_commit_time = cfg.max_commit_time
	search_look_rate = cfg.search_look_rate
	tactic_interval = cfg.tactic_interval
	run_enabled = cfg.run_enabled
	run_min_distance = cfg.run_min_distance
	run_start_fraction = cfg.run_start_fraction
	posture_enabled = cfg.posture_enabled
	posture_dwell = cfg.posture_dwell
	entry_guard = cfg.entry_guard
	entry_guard_range = cfg.entry_guard_range
	entry_guard_rearm = cfg.entry_guard_rearm
	entry_secure_time = cfg.entry_secure_time
	watch_lost_gaze = cfg.watch_lost_gaze
	low_ammo_fraction = cfg.low_ammo_fraction
	squad = cfg.squad
	_loco.arrive_dist = cfg.arrive_dist
	_watch.look_ahead = cfg.watch_look_ahead
	_watch.door_dwell = cfg.watch_door_dwell
	_watch.lost_gaze = cfg.watch_lost_gaze
	_watch.look_rate = cfg.search_look_rate
	_coverage.spacing = cfg.search_coverage_spacing
	_coverage.target_fraction = cfg.search_coverage_target
	_coverage.budget_max = cfg.search_coverage_budget
	_coverage.approach = cfg.search_coverage_approach
	_coverage.margin = cfg.search_coverage_margin
	_coverage.look_rate = cfg.search_look_rate
	_combat.shoot_range = cfg.shoot_range
	_combat.punch_range = cfg.punch_range
	_combat.ring_radius = cfg.combat_ring_radius
	_combat.cover_time = cfg.cover_time
	_combat.fire_cooldown = cfg.fire_cooldown
	_combat.fire_burst = cfg.fire_burst
	_combat.back_off_time = cfg.back_off_time
	_combat.reposition_interval = cfg.reposition_interval
	_combat.auto_reload = cfg.auto_reload
	_apply_entry_config(cfg)


## Set the entry module's tunables from `cfg` (`apply_config`): the controller's Entry exports, its
## `squad` and the look rate.
func _apply_entry_config(cfg: Node) -> void:
	_entry.ready_timeout = cfg.entry_ready_timeout
	_entry.listen_time = cfg.entry_listen_time
	_entry.follow_gap = cfg.entry_follow_gap
	_entry.pie_dwell = cfg.entry_pie_dwell
	_entry.corner_dwell = cfg.entry_corner_dwell
	_entry.rear_time = cfg.rear_security_time
	_entry.cover_time = cfg.entry_cover_time
	_entry.watch_dwell = cfg.entry_watch_dwell
	_entry.approach_time = cfg.entry_approach_time
	_entry.order_ready_cap = cfg.order_ready_cap
	_entry.squad = cfg.squad
	_entry.look_rate = cfg.search_look_rate


# --- Read-only views -------------------------------------------------------------------------


## Read-only: the decision path the NPC is carrying out, as ids ("combat/t_12/flank/side_left").
func current_act() -> String:
	return "/".join(_path) if not _path.is_empty() else "hold"


## Read-only: the decision path as labels, joined ("SEARCH - ENTER - the doorway into the kitchen").
func path_label() -> String:
	return " - ".join(_labels)


## Read-only: the running order's decision path, as ids and as labels (`{ path, labels }`).
func order() -> Dictionary:
	return { "path": _path.duplicate(), "labels": _labels.duplicate() }


## Whether the running entry turned from quiet to a bang since the last call (E17, a late reason):
## true once.
func take_entry_turned() -> bool:
	return _primitive == &"entry" and _entry.take_turned()


## Re-adopt the running entry order as a bang entry under `path` and `labels` (an ENTER turned STUN
## ENTRY): the entry runs on where it is, only what it is called and its `bang` param change.
func adopt_bang(path: Array, labels: Array) -> void:
	_path = path
	_labels = labels
	_params["bang"] = true


## Read-only: the broad mode of the running leaf (combat / investigate / search / idle / hold).
func intent() -> String:
	return str(_path[0]) if not _path.is_empty() else "hold"


## Read-only: whether the NPC is fighting (so a fresh hit doesn't force a re-decision).
func in_combat() -> bool:
	return intent() == "combat"


## Read-only: whether the running choice is still in progress (en route, fighting, using an object)
## rather than finished (arrived, holding) — the planner only offers "keep your current plan" for
## one still in progress.
func ongoing() -> bool:
	match _primitive:
		&"move":
			return not _arrived
		&"engage", &"melee", &"interact", &"throw", &"defend", &"ambush", &"follow":
			return true
		&"reload":
			return _reloading
		&"entry":
			return _entry_pending or _entry.phase not in ["", "done"]
	return false


## Read-only: the engaged contact's last-seen inside/outside state packed into the salient key — the
## controller re-decides when this (or the known-hostile set) changes. A throw order keeps its
## target in the key after the contact ages out (`_throw_target`), so the lapse is no change: the
## throw goes on to the spot it was offered on (G17). A target that died leaves the key, so the NPC
## re-decides.
func salient_key() -> String:
	var ids: Array = _hostiles.map(func(c): return c["id"])
	var engaged := _engage_id != 0
	var held := _throw_target()
	if held != 0 and not ids.has(held):
		ids.append(held)
		engaged = true  # `_engage_inside` keeps the lost contact's last-seen state.
	ids.sort()
	return "%s|%s" % [str(ids), str(_engage_inside) if engaged else "-"]


## The hostile a running throw order was offered on (its `target_id`), also while an entry detour
## has paused it, while the perception still holds it as lost (aged out of the contacts, not dead:
## `lost_hostiles()` drops the dead); 0 for none. The throw is aimed at that hostile's last-known
## spot and keeps it when the contact ages out on the way (G17).
func _throw_target() -> int:
	var id := 0
	if _primitive == &"throw":
		id = int(_params.get("target_id", 0))
	elif _primitive == &"entry" and _resume.get("primitive") == &"throw":
		id = int((_resume["params"] as Dictionary).get("target_id", 0))
	if (id == 0
			or _perception == null
			or not _perception.lost_hostiles().any(func(c): return c["id"] == id)):
		return 0
	return id


## Read-only: the FULL decision path the NPC is carrying out, every level from the broad mode down
## to the concrete option ("COMBAT - Intruder - FLANK - their left side (kitchen)"), then where it
## is in carrying it out — for debug overlays and the HUD.
func debug_status() -> String:
	var line: String = " - ".join(_labels) if not _labels.is_empty() else "HOLD"
	var state := _progress()
	if state != "":
		line += "  · " + state
	if _posture != &"stand":
		line += "  · " + "crouching"
	if _perception != null and _perception.under_fire():
		line += "  ⚠ under fire"
	return line


## Read-only: what the NPC is doing, for Von's "current activity" line: the full path, its progress
## and how long it has been at it.
func activity_text() -> String:
	if _labels.is_empty():
		return ""
	var secs := int((GameClock.msec() - _leaf_ms) / 1000.0)
	return "%s (%s, for %ds)" % [" - ".join(_labels), _progress(), secs]


## Where the running primitive stands ("en route", "in position, ducking behind cover", …).
func _progress() -> String:
	match _primitive:
		&"move", &"melee", &"interact", &"reload":
			return _walk_progress()
		&"engage":
			return _engage_progress()
		&"entry":
			return ENTRY_PROGRESS.get(_entry.phase, "heading for the door")
		&"throw":
			return _throw_progress()
		&"defend", &"ambush", &"follow":
			return _post_progress()
	return "waiting" if not _labels.is_empty() else ""


## Where a move, a melee, an interaction or a reload stands ("en route", "closing in to punch", …).
func _walk_progress() -> String:
	match _primitive:
		&"move":
			return "reached it" if _arrived else ("running" if _running else "en route")
		&"melee":
			return "running in to punch" if _running else "closing in to punch"
		&"interact":
			return "using it" if _in_interaction else "walking to it"
	return "reloading"


## Where an engage stands: on its way into position, waiting in ambush, or peeking and ducking.
func _engage_progress() -> String:
	if not _arrived:
		return "running into position" if _running else "moving into position"
	if _params.get("style", &"peek_cover") == &"ambush":
		return "in ambush, waiting for a shot"
	return "in position, %s" % ("ducking behind cover"
			if _combat.phase == "cover"
			else "looking for a shot")


## Where a throw stands: walking to its throw spot, throwing, or waiting for the grenade to go off.
func _throw_progress() -> String:
	if _combat.throw_stage == "walk":
		return "walking to the throw spot"
	return "throwing it" if _throw_wait < 0.0 else "waiting for it to go off"


## Where a defend, an ambush or a follow stands: on its way, or at its post or its spot.
func _post_progress() -> String:
	match _primitive:
		&"defend":
			return "holding the room" if _arrived else "on the way to its post"
		&"ambush":
			return "waiting in ambush" if _arrived else "on the way to its post"
	return "by its leader" if _arrived else "keeping up with its leader"


## Read-only: the full primitive/engagement/commitment state as structured data, for the
## controller's `debug_state()` snapshot. Built from live state (never mutates); JSON-safe.
func debug_state() -> Dictionary:
	return {
		"act": current_act(),
		"labels": " - ".join(_labels),
		"primitive": String(_primitive),
		"params": _json_safe(_params),
		"arrived": _arrived,
		"running": _running,
		"posture": String(_posture),
		"reloading": _reloading,
		"engage": str(_engage_node.name) if is_instance_valid(_engage_node) else "",
		"engage_id": _engage_id,
		"engage_inside": _engage_inside,
		"combat_phase": _combat.phase,
		"holds_fire": _combat.holds_fire() if _character != null else false,
		"hold_ground": _hold_ground,
		"hostiles_known": _hostiles.size(),
		"gaze": {
			"mode": _gaze,
			"threat": str(_threat["node"].name)
				if not _threat.is_empty() and is_instance_valid(_threat["node"])
				else "",
		},
		"in_interaction": _in_interaction,
		"evade": _json_safe(_evade) if not _evade.is_empty() else {},
		"timers": {
			"commit": _commit_timer,
			"tactic": _tactic_timer,
			"interaction": _interaction_timer,
			"fire": _combat.fire_timer,
			"cover": _combat.cover_timer,
			"combat_dest": _combat.dest_timer,
		},
		"entry": _json_safe(debug_entry()),
		"loco": _loco.debug_state(),
		"order": _order_leaf(),
	}


## The order leaf the NPC is carrying out (a walk that began at the ORDER node, `docs/leadership.md`
## LD6), as `{ path, primitive, params, paused }` (JSON-safe; `paused` while an entry detour of the
## entry guard holds it, its primitive and params then the paused order's, not the detour's), or {}
## when it carries out no order. `debug_state()`'s own `primitive` and `params` are always the
## running ones.
func _order_leaf() -> Dictionary:
	if _path.is_empty() or str(_path[0]) != "order":
		return {}
	var paused := _primitive == &"entry" and not _resume.is_empty()
	return {
		"path": current_act(),
		"primitive": String(_resume["primitive"] if paused else _primitive),
		"params": _json_safe(_resume["params"] if paused else _params),
		"paused": paused,
	}


## Read-only: the running tactical entry (doorway, slot, side, phase, what the pie saw, the corner),
## or {} when the NPC isn't entering. See entry.gd `debug()`.
func debug_entry() -> Dictionary:
	return _entry.debug() if _primitive == &"entry" else {}


## Read-only, for the entry debug overlays: the running entry as world-space data (entry.gd
## `debug_view`, under `entry`; {} when none) and the entry guard's picture under `guard`: whether a
## detour is running and the order it paused (`resume_point`, `resume_label`), the doorways it is
## leaving alone (`rearm`: `{ opening, left }`), its `range`, the next uncleared doorway on the
## current walk (`ahead`: `{ opening, into, dist, pos }`, or {}), the rects of the rooms this NPC
## regards as cleared (`cleared_rooms`), and the doorway views its walks keep out of (`views`:
## `{ id, into, poly }`, with `round_views` true while the walk goes round them on the avoid map).
## Computed only when asked; nothing reads it back.
func debug_entry_view() -> Dictionary:
	var guard := {
		"detour": _primitive == &"entry" and not _resume.is_empty(),
		"resume_point": _resume.get("point", Vector2.INF),
		"resume_label": " - ".join(_resume.get("labels", [])),
		"rearm": [],
		"range": entry_guard_range,
		"ahead": {},
		"cleared_rooms": [],
		"views": [],
		"round_views": _loco.debug_state().get("way", "") == "doors",
	}
	for id in _guard_off:
		var left: float = float(_guard_off[id]) - _guard_clock
		if left > 0.0:
			guard["rearm"].append({ "opening": id, "left": left })
	if _perception != null:
		guard["views"] = _perception.avoided_views()
		for r in rooms:
			if _perception.is_cleared(str(r["key"])):
				guard["cleared_rooms"].append(r["rect"])
		var walk: Dictionary = _loco.path_ahead() if _primitive != &"entry" else {}
		if not walk.is_empty():
			var gate: Dictionary = _perception.threshold_ahead(
				walk["path"], walk["index"], GUARD_PREVIEW_RANGE,
			)
			if not gate.is_empty():
				var geo: Dictionary = _perception.entry_geometry(gate["opening"], gate["into"])
				if not geo.is_empty():
					gate["pos"] = geo["pos"]
					guard["ahead"] = gate
	return { "entry": _entry.debug_view() if _primitive == &"entry" else {}, "guard": guard }


## Whether the NPC is committed: crossing a doorway, or with its arm drawn back to throw (a grenade
## cannot be called back). The controller holds every re-decision until it is through.
func committed() -> bool:
	return ((_primitive == &"entry" and _entry.committed())
			or (_primitive == &"throw" and _combat.throw_stage == "windup"))


## The entry steps to radio since the last call (claims in `StackClaim`'s fields), with the
## doorway, the room it leads into, slot and side they are about; the controller posts them as
## callouts.
func take_entry_calls() -> Array:
	var out: Array = []
	for c in _entry.take_calls():
		c.merge({
			"opening": _entry.opening,
			"into": _entry.into,
			"slot": _entry.slot,
			"side": _entry.side,
		})
		out.append(c)
	return out


## Read-only: the running search-coverage state, for the search debug overlay. `active` is true only
## while a `look_around` move is actually covering a room (arrived, not yet resolved); `points` are
## all the room's sample points, `unseen` the ones still to be seen, `target` the one being looked
## at now.
func debug_coverage() -> Dictionary:
	var out: Dictionary = _coverage.debug()
	out["active"] = (_primitive == &"move" and _look_around and _arrived and not _resolved) \
		or (_primitive == &"entry" and _entry.phase == "clear")
	return out


## Read-only: the running combat / movement / interaction state as world-space data (Vector2s, not
## the JSON-safe digest), for the combat, territory and targets debug overlays. The NPC's body gives
## its aim point and the fire-line query. A pure read — the line query only casts a ray.
func debug_combat() -> Dictionary:
	var engaged := _engage_id != 0
	var in_range := false
	var fire_clear := false
	if engaged and _character != null:
		in_range = _character.global_position.distance_to(_engage_pos) <= _combat.shoot_range
		fire_clear = in_range and _perception.has_line_to(_engage_node, _engage_pos)
	var fighting := _primitive in [&"engage", &"melee"]
	var obj_pos = null
	if _primitive == &"interact" and is_instance_valid(_target_obj) and _target_obj is Node2D:
		obj_pos = (_target_obj as Node2D).global_position
	return {
		"primitive": _primitive,
		"style": _params.get("style", &"peek_cover") if _primitive == &"engage" else &"",
		"engaged": engaged,
		"engage_pos": _engage_pos,
		"engage_inside": _engage_inside,
		"hold_ground": _hold_ground,
		"in_range": in_range,
		"fire_clear": fire_clear,
		"shoot_range": _combat.shoot_range,
		"punch_range": _combat.punch_range,
		"combat_phase": _combat.phase if fighting else "",
		"cover_timer": _combat.cover_timer,
		"cover_time": _combat.cover_time,
		"fire_timer": _combat.fire_timer,
		"fire_cooldown": _combat.fire_cooldown,
		"combat_dest": _combat.dest
			if _primitive == &"engage" and _arrived and _combat.dest != Vector2.ZERO
			else null,
		"aim_point": _character.aim_point if _character != null else Vector2.ZERO,
		"reloading": _reloading,
		"requested_point": _params["point"] if _params.has("point") else null,
		"point": (_point as Variant) if _params.has("point") else null,
		"arrived": _arrived,
		"arrive_room": _arrive_room,
		"object_pos": obj_pos,
		"in_interaction": _in_interaction,
		"interaction_timer": _interaction_timer,
		"interaction_dwell": interaction_dwell,
		"watch_pos": _hostiles[0]["pos"]
			if _primitive == &"hold" and not _hostiles.is_empty()
			else null,
		"reachable": _loco.debug_state().get("reachable", true),
		"timers": { "commit": _commit_timer, "tactic": _tactic_timer },
	}


## Read-only: the movement-progress sample (seconds stalled, recent trail) for the stuck overlay.
func debug_progress() -> Dictionary:
	return _loco.debug_progress()


## A params dict with points as [x, y] and objects as names, so an observer can serialize it.
func _json_safe(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var v = d[k]
		if v is Vector2:
			out[k] = [int(v.x), int(v.y)]
		elif v is Object:
			out[k] = str(v.name) if is_instance_valid(v) and v is Node else "?"
		else:
			out[k] = v if v is bool or v is int or v is float else str(v)
	return out


# --- Adopting a decision ---------------------------------------------------------------------


## Adopt the planner's leaf `{ path, labels, primitive, params }`: capture its destination (snapped
## onto the navmesh), its target and its object, and commit to it.
func set_leaf(leaf: Dictionary) -> void:
	# The decision made with the order known has landed (the controller hands only that one, or a
	# later one).
	_awaiting_order = false
	if not _evade.is_empty():
		# Running from a grenade: a decision that was in flight is stale by the burst, which ends in
		# a new one.
		return
	if committed() and _resume.is_empty():
		# Crossing a doorway on its own ENTER, throwing the bang, or winding up a throw: a decision
		# that was in flight waits (it ends in a re-decision). The bang's thrower (E17) throws
		# first, then decides again from where it stands (`_apply_entry`).
		_held = _held or (_primitive == &"entry" and _entry.throwing())
		return
	if _same_order(leaf):
		# The ordered stack it is carrying out, decided again: its entry (or the detour paused in
		# front of it) runs on (LD9).
		return
	var carry := {}
	if (_primitive == &"entry"
			and not _resume.is_empty()
			and (committed() or _guards(leaf, _entry.into))):
		# A detour's entry carries on: the new order replaces the one paused behind it (a fight that
		# began, the same order decided again), and the entry is not torn down at its stack or in
		# its threshold.
		carry = { "primitive": _primitive, "params": _params, "pending": _entry_pending }
	else:
		_drop_detour()
		_entry_pending = false
		_entry.abandon()  # A new choice ends any entry in progress (the stack is told).
	_adopt(leaf)
	if not carry.is_empty():
		_stash_order()
		_primitive = carry["primitive"]
		_params = carry["params"]
		_entry_pending = carry["pending"]


## Whether `leaf` is the ordered stack the NPC is already carrying out (the same `order_id`), its
## entry running or paused behind a detour of the entry guard (`docs/leadership.md` LD9).
func _same_order(leaf: Dictionary) -> bool:
	var id = (leaf.get("params", {}) as Dictionary).get("order_id")
	if id == null or leaf.get("primitive") != &"entry":
		return false
	var running: Dictionary = (_resume
			if not _resume.is_empty()
			else { "primitive": _primitive, "params": _params })
	if (running["primitive"] != &"entry"
			or str((running["params"] as Dictionary).get("order_id", "")) != str(id)):
		return false
	return not _resume.is_empty() or _entry_pending or not _entry.phase in ["", "done"]


## Whether the NPC is on an ordered stack's way to its door (`docs/leadership.md` LD9): running the
## entry an order gave it, or a detour of the entry guard paused in front of one. Its walk is
## guarded whatever `entry_enabled` says (D4).
func _ordered_stack() -> bool:
	if _primitive == &"entry" and _ordered_entry(_params):
		return true
	return (not _resume.is_empty()
			and _resume["primitive"] == &"entry"
			and _ordered_entry(_resume["params"]))


## Whether the running entry is a join (LD24) whose order has ended (done: the room cleared by the
## rest of the stack) while the member is still on its way to the stack or in it, where its entry
## would never end on its own (LD25, D26): once per leaf.
func _join_over() -> bool:
	return (StackClaim.is_join(_params)
			and not _join_done
			and not _order_live()
			and _entry.phase in ["approach", "stack"])


## Whether an entry leaf's `params` are an ordered stack's, which goes in the order's way (LD9): an
## order's that is no join (a join is the member's own entry joining its leader's stack, LD24).
static func _ordered_entry(params: Dictionary) -> bool:
	return params.has("order_id") and not StackClaim.is_join(params)


## Whether the entry guard applies to `leaf` for a doorway into room `into`: a walk (move / engage /
## interact, or a throw from a throw spot) that is not a retreat, while the NPC is not under fire,
## or, under fire, into the room the shots came from (`_into_the_shots`).
func _guards(leaf: Dictionary, into: String) -> bool:
	var params: Dictionary = leaf.get("params", {})
	var prim: StringName = leaf.get("primitive", &"hold")
	var walks: bool = (prim in [&"move", &"engage", &"interact", &"defend", &"ambush"]
			or (prim == &"throw" and bool(params.get("walk", false))))
	return (entry_guard
			and walks
			and bool(params.get("entry_guard", true))
			and (not _perception.under_fire() or _into_the_shots(into)))


## Whether a walk into room `into` is a walk into the shots (E9): the NPC was shot at from that
## room, whether it sees the shooter or not. Under fire it still goes in by entry, not straight
## through the doorway.
func _into_the_shots(into: String) -> bool:
	return into != "" and _perception.shots_from_room(into)


## Take `leaf` as the running order.
func _adopt(leaf: Dictionary) -> void:
	_held = false
	_join_done = false
	_primitive = leaf.get("primitive", &"hold")
	_params = leaf.get("params", {})
	_path = leaf.get("path", [])
	_labels = leaf.get("labels", [])
	_leaf_ms = GameClock.msec()
	_arrived = false
	_act_armed = false
	_commit_timer = max_commit_time
	_arrive_room = str(_params.get("arrive_room", ""))
	_look_around = bool(_params.get("look_around", false))
	# Room sample points are built on arrival, once we know which room we're in.
	_coverage.reset()
	_watch.reset()
	_point = _loco.reachable(_params["point"]) if _params.has("point") else Vector2.ZERO
	_target_obj = null
	_combat.end_throw()
	_throw_wait = -1.0
	_engage_id = 0
	var target_id: int = _params.get("target_id", 0)
	if target_id != 0:
		_engage(target_id)
	match _primitive:
		&"engage", &"melee":
			if _engage_id == 0:
				_primitive = &"hold"  # The target was lost while deciding; re-decide.
				_resolved = true
				return
			_combat.begin_fight()
			_tactic_timer = tactic_interval
			_perception.note_engaged()  # Commit to the fight (refreshed by firing).
		&"interact":
			_target_obj = _params.get("object")
			_interact_id = _params.get("id", "")
		&"reload":
			_reload_started = false
		&"entry":
			_entry_pending = true
		&"throw":
			_begin_throw_order()
		&"defend", &"ambush":
			_point = _loco.reachable(_params.get("spot", _character.global_position))
		&"follow":
			_follow_to = Vector2.INF
	# (Refused: an order kept and held, no room for it.)
	_say_order_step("refused" if _params.get("refused", false) else "moving")


## Start the throw order in `_params` afresh: with a throw spot (`walk`), from the walk to it (a
## throw resumed after a detour's entry, whose bang may have used the throwing hands, starts here
## too).
func _begin_throw_order() -> void:
	_throw_kind = _params.get("kind", &"")
	_throw_spot = _params.get("point", Vector2.ZERO)
	_throw_seen = false
	_throw_wait = -1.0
	var from: Vector2 = (_params.get("from", Vector2.INF)
			if _params.get("walk", false)
			else Vector2.INF)
	_combat.begin_throw(
		int(_params.get("slot", -1)), _throw_spot, _perception.grenade_reach(_throw_kind),
		Vector2.INF if from == Vector2.INF else _loco.reachable(from),
	)


## The characters a walk accounts for: every contact the NPC knows of, less one out of sight whose
## last-known spot, near enough to matter (`WALK_BODY_RANGE`), it can see now with nobody on it (it
## has moved on unseen).
func _walk_bodies() -> Array:
	var here: Vector2 = _character.global_position
	var spots: Array = []
	for c in _known:
		if not c["visible"] and (c["pos"] as Vector2).distance_to(here) <= WALK_BODY_RANGE:
			spots.append(c["pos"])
	if spots.is_empty():
		return _known
	var empty: Array = _perception.visible_points(spots)
	if empty.is_empty():
		return _known
	return _known.filter(func(c): return c["visible"] or not empty.has(c["pos"]))


## Fight known contact `id`: capture its body and last-known position (no-op when it isn't known).
func _engage(id: int) -> void:
	for c in _hostiles:
		if c["id"] == id:
			_engage_id = id
			_engage_node = c["node"]
			_engage_pos = c["pos"]
			_engage_inside = c.get("inside", false)
			return


## A steady stance for when no decision can be had (Von unreachable): stop and watch any known
## hostile.
func fallback() -> void:
	_awaiting_order = false
	_drop_detour()
	_entry.abandon()  # No decision to be had: an entry in progress is given up (the stack is told).
	_primitive = &"hold"
	_params = {}
	_path = []
	_labels = []
	_target_obj = null


# --- Per-tick bookkeeping ---------------------------------------------------------------------


## Resolve what the NPC currently knows from the perception's contact list (the engaged contact's
## last-known body/position/inside state) and advance the commitment timers. If the engaged contact
## is no longer known (its sighting decayed) or no longer hostile, a fight retargets to the nearest
## other known hostile; with none left, a leaf that needs a target ends and this returns true so the
## controller re-decides. All acting reads these rather than true positions, so the NPC only ever
## acts on what it has perceived.
func update_known(known: Array, delta: float) -> bool:
	_commit_timer -= delta
	_tactic_timer -= delta
	_known = known
	_hostiles = known.filter(func(c): return c["hostile"])
	if _throw_target_gone():
		_end_throw()
		return true
	if _engage_id == 0:
		return false
	var engaged: Dictionary = {}
	for c in _hostiles:
		if c["id"] == _engage_id:
			engaged = c
	if not engaged.is_empty() and not engaged["visible"]:
		# The one it is fighting has slipped out of sight and another stands in plain view: fight
		# that one.
		var seen: Array = _hostiles.filter(func(c): return c["visible"])
		if not seen.is_empty():
			engaged = seen[0]
			_engage_id = engaged["id"]
	if engaged.is_empty():
		engaged = _hostiles[0] if not _hostiles.is_empty() else {}
		_engage_id = engaged.get("id", 0)
	if not engaged.is_empty():
		_engage_node = engaged["node"]
		_engage_pos = engaged["pos"]
		_engage_inside = engaged.get("inside", false)
		return false
	if _needs_target():
		_primitive = &"hold"
		return true
	return false


## A throw order not yet in its wind-up whose target the NPC no longer knows of at all, neither as a
## contact nor as lost (it died, or was forgotten): there is nobody left on its spot, so the throw
## ends and the NPC re-decides (G17).
func _throw_target_gone() -> bool:
	if _primitive != &"throw" or _combat.throw_stage in ["windup", "away"]:
		return false
	var id := int(_params.get("target_id", 0))
	return id != 0 and not _hostiles.any(func(c): return c["id"] == id) and _throw_target() == 0


## Whether the running leaf is pointless without its target (a fight, or a move aimed at it).
func _needs_target() -> bool:
	return (_primitive in [&"engage", &"melee"]
			or (_primitive == &"move" and _params.get("aim") == &"target"))


## Advance an active interaction: hold it until its dwell runs out, the character leaves it, or the
## controller forces a rethink (`force`); then end it and flag the task resolved. Returns true while
## the NPC is STILL interacting (the controller should do nothing more this tick).
func service_interaction(delta: float, force: bool) -> bool:
	if not _in_interaction:
		return false
	_interaction_timer -= delta
	if force or not _character.is_busy() or _interaction_timer <= 0.0 or not _evade.is_empty():
		_character.end_interaction()
		_in_interaction = false
		_resolved = true  # Pick the next step right away rather than wait out the cadence.
		return false
	return true


## Whether a committed task just finished (arrived / interaction ended / target lost while
## deciding), or its walk is blocked (`resolve_reason`). Clears the flag; the controller forces a
## re-decision when it returns true.
func take_resolved() -> bool:
	var r := _resolved
	_resolved = false
	_resolve_reason = ""
	return r


## Why the task is resolved, read before `take_resolved()`: "way blocked" when a body seals the only
## way of its walk and stays, "after the bang" when the bang's thrower has thrown with a decision
## held off ("" = it finished).
func resolve_reason() -> String:
	return _resolve_reason


## The investigation lead the running move has reached (its `lead` param), or "" — so the controller
## can tell perception it was checked.
func reached_lead() -> String:
	return str(_params.get("lead", "")) if _primitive == &"move" and _arrived else ""


## Whether the running leaf wants a new decision now: a fight still moving into position holds until
## its safety cap; once in position it re-asks its tactic every `tactic_interval` or when the
## engagement lapses; a move or approach holds until it completes (which forces a decision) or its
## safety cap runs out; a hold follows the decide cadence.
func wants_decision(decide_timer_elapsed: bool) -> bool:
	match _primitive:
		&"engage", &"melee":
			return _fight_wants_decision()
		&"move":
			# Hold through room coverage; it ends itself (all seen, or the budget runs out).
			var covering := _look_around and _arrived and not _resolved
			return not covering and _commit_timer <= 0.0
		&"interact", &"reload", &"throw":
			return _commit_timer <= 0.0
		&"entry", &"follow":
			# An entry ends itself: the room clear, or the entry given up. A follower keeps with its
			# leader until something forces a decision.
			return false
		&"defend", &"ambush":
			return _post_wants_decision()
	return decide_timer_elapsed


## `wants_decision` for an engage or a melee: an engage still moving into position holds until its
## safety cap; in position (and a melee) it re-asks its tactic every `tactic_interval` or when the
## engagement lapses.
func _fight_wants_decision() -> bool:
	if _primitive == &"engage" and not _arrived:
		return _commit_timer <= 0.0
	return _tactic_timer <= 0.0 or not _perception.engaged_fresh()


## `wants_decision` for a defend or an ambush, held at its post as long as its order stands.
func _post_wants_decision() -> bool:
	if _primitive == &"ambush":
		# It holds its post as long as the order stands; first contact ends the order (D18), and
		# the NPC then fights on its own.
		return not _order_live() or (not _arrived and _commit_timer <= 0.0)
	# On the way, the walk's safety cap; at its post it holds as long as the order stands, until a
	# fight it began from there (its shots keep it engaged) is the decision's to weigh, in the room
	# (LD8).
	return _commit_timer <= 0.0 if not _arrived else _perception.engaged_fresh()


# --- Running the primitive --------------------------------------------------------------------


## Carry out the running primitive this tick.
func apply(delta: float) -> void:
	if _primitive != &"follow":
		_catching_up = false
	_combat.tick(delta)
	_set_up_walk(delta)
	if not _evade.is_empty():
		_apply_evade(delta)
		return
	match _primitive:
		&"move":
			_apply_move(delta)
		&"engage":
			_apply_engage(delta)
		&"melee":
			_apply_melee()
		&"interact":
			_apply_interact()
		&"reload":
			_apply_reload()
		&"entry":
			_apply_entry(delta)
		&"throw":
			_apply_throw(delta)
		&"defend", &"ambush":
			_apply_defend()
		&"follow":
			_apply_follow()
		_:
			_apply_hold()
	if _awaiting_order and not committed() and _walking():
		# The order is being decided on: stop the walk it replaces, as an arrived move stands.
		_character.move_input = Vector2.ZERO
	if _loco.take_blocked():
		_way_blocked()
	_apply_watch(delta)
	_guard_clock += delta
	_entry_guard()
	_combat.continue_burst()
	_character.run_input = _should_run()
	_combat.apply_back_off(delta)
	_apply_posture(delta)
	_running = _character.is_running()
	_posture = _character.posture()
	_reloading = _character.ammo.is_reloading()


## Tell the locomotion what this tick's walk accounts for: the bodies it knows of, the one a melee
## closes on, and whether it keeps out of the doorway views (and the room an entry goes into).
func _set_up_walk(delta: float) -> void:
	_loco.sample(delta)  # Observation only (stuck overlay); never alters the tick.
	# Every walk accounts for the characters the NPC knows of, and only those.
	_loco.bodies = _walk_bodies()
	# A melee closes on its target: no walk round it.
	_loco.ignore_id = _engage_id if _primitive == &"melee" else 0
	_perception.ordered_walk = _ordered_stack()
	_loco.avoid_doors = _keeps_out_of_views()
	_loco.avoid_entering = ("%s>%s" % [_entry.opening, _entry.into]
			if _primitive == &"entry" and _entry.opening != ""
			else "")


## An order was taken (`on`, the frame it arrives: `docs/leadership.md` LD5) or the decision made
## knowing it has landed (`set_leaf` and `fallback` clear it too): until then a walk the order
## replaces stops (`_walking`), as an arrived move stands, while a fight goes on (a move chosen
## under COMBAT included); the watch stage still looks and shoots. A crossing or a bang's throw
## (`committed()`) is not stopped in the doorway.
func await_order(on: bool) -> void:
	_awaiting_order = on


## Whether the running primitive is on a walk an order replaces (LD6): a move that is not chosen
## under COMBAT (a search's walk and cover, an investigation's, an idle walk), an entry's approach
## to its slot, a defend or ambush walk to its post, a throw's walk to its throw spot, an
## interaction's walk to its object. Not a fight (an engage arrived or on its way, a melee, a
## reload, a hold, and a move chosen under COMBAT: an advance, a retreat, a locate, whose path
## starts at `combat`) nor the rest of an entry (the pie, the crossing, the corner, the clear, the
## cover, the rear: one stopped there stands in the doorway's funnel).
func _walking() -> bool:
	match _primitive:
		&"move":
			return not in_combat()
		&"entry":
			return _entry.phase == "approach"
		&"defend", &"ambush", &"follow":
			return not _arrived
		&"throw":
			return _combat.throw_stage == "walk"
		&"interact":
			return (not _in_interaction
					and _target_obj != null
					and is_instance_valid(_target_obj)
					and not _interaction_in_reach())
	return false


## Whether the walk the running primitive is on keeps out of the doorway views (E18): the walks the
## entry guard covers, so a move, an engage or an interact that is not a retreat, a throw's walk to
## its throw spot, and an entry's approach to its stack (its other walks, the pie and the crossing,
## are the entry's own), while the NPC is not under fire. Not an evade. An ordered stack's walk does
## whatever `entry_enabled` says (D4).
func _keeps_out_of_views() -> bool:
	if (not entry_guard
			or not (_perception.entry_enabled or _ordered_stack())
			or not _evade.is_empty()
			or _perception.under_fire()):
		return false
	if _primitive == &"entry":
		return _entry.phase == "approach"
	if _primitive == &"throw":
		return _combat.throw_stage == "walk"
	return (_primitive in [&"move", &"engage", &"interact", &"defend", &"ambush"]
			and bool(_params.get("entry_guard", true)))


## A body seals the only way of the walk the primitive is on and stays (`Locomotion.take_blocked`):
## re-plan, so the NPC is never held for ever. A move, an engage, a melee or an interact re-decides
## (another walk, or the same one held), and so does a throw still walking to its throw spot or
## closing on its spot (not once the wind-up has begun); an entry re-plans its own walk
## (`Entry.way_blocked`) and, when it gives the entry up, re-decides too, or, as a detour, hands the
## walk back to the order it paused. An evade (not a primitive: it replaces the order) holds the
## best spot it has until the burst.
func _way_blocked() -> void:
	if _primitive in [&"move", &"engage", &"melee", &"interact", &"defend", &"ambush"]:
		_resolved = true
		_resolve_reason = "way blocked"
	elif _primitive == &"throw" and _combat.throw_stage in ["walk", "aim"]:
		_end_throw()
		_resolve_reason = "way blocked"
	elif _primitive == &"entry" and _entry.way_blocked():
		_finish_entry()
		if _resolved:
			_resolve_reason = "way blocked"
	elif _primitive == &"follow":
		_arrived = true  # It stands where it is held until its spot moves on.


## The watch stage (docs/gaze-and-fire.md), run after the primitive has steered: an NPC is always
## either looking at (and, when it can, shooting) a threat, or watching its doors, never a wall and
## never with its back to a known threat. A threat (`Watch.threat`: the hostile it is fighting or
## the nearest it sees, else one it saw a moment ago with a clear line to where it was) takes the
## eyes and the gun whatever the primitive is doing: `Combat` shoots it as soon as a shot is on, and
## an empty gun is reloaded. A melee and an engaged NPC in position fight their own target and aim
## at it themselves; an interaction has its own gaze. With nothing to look at, a resting NPC (a
## hold, a reload, a move that has arrived) turns among its room's doorways.
func _apply_watch(delta: float) -> void:
	_threat = {}
	_gaze = "primitive"
	if _character.is_busy() or _own_gaze():
		return
	var t: Dictionary = _watch.threat(_hostiles, _engage_id)
	if not t.is_empty() and not t["visible"] and not _perception.has_line_to(t["node"], t["pos"]):
		t = {}  # Remembered behind a wall: not worth staring at the wall for.
	if not t.is_empty():
		_threat = t
		_gaze = "threat"
		_character.aim_point = t["pos"]
		_combat.fire_at_will(t)
		if not _entry.committed():
			_combat.reload_if_dry()
		return
	if _resting():
		_gaze = "doors"
		var door = _params.get("door_pos") if _primitive in [&"defend", &"ambush"] else null
		if door is Vector2:
			# A defender's gun on its own doorway (D2), an ambusher's on the threshold (LD15).
			Watch.ease_gaze(_character, door, search_look_rate, delta)
		else:
			_watch.idle_gaze(delta)


## Whether the running primitive keeps its own gaze this tick, so the watch stage leaves it be: a
## melee, an interaction, an engage in position, a throw taking the grenade in hand and throwing it,
## an entry's bang.
func _own_gaze() -> bool:
	match _primitive:
		&"melee", &"interact":
			return true
		&"engage":
			return _arrived
		&"throw":
			# Taking the grenade in hand and throwing it: aimed at the spot, not shot at the threat.
			return _combat.throw_stage not in ["walk", "away"]
		&"entry":
			return _entry.phase == "bang"  # Turned away from the door for the stun.
	return false


## Whether the running primitive leaves the NPC standing with nowhere in particular to look: a hold,
## a reload, a move that has arrived (and is not covering the room by sight).
func _resting() -> bool:
	match _primitive:
		&"hold", &"reload":
			return true
		&"move":
			return _arrived and not _look_around
		&"throw":
			return _combat.throw_stage == "away"
		&"defend", &"ambush":
			return _arrived
	return false


## The gun ran dry mid-fight: the task is resolved, so the controller re-decides (the empty gun is
## in the snapshot now).
func _on_dry() -> void:
	_resolved = true


## Take the posture `_wanted_posture` asks for. Standing back up is never delayed (a run, the end of
## a fight); a crouch is held for `posture_dwell` before it is dropped, so a peek-and-duck does not
## flicker. A change the character refuses (its own pacing, an interaction) is simply asked again
## next tick.
func _apply_posture(delta: float) -> void:
	_posture_hold = maxf(_posture_hold - delta, 0.0)
	var want := _wanted_posture()
	if want == _character.posture() or (want != &"stand" and _posture_hold > 0.0):
		return
	if _character.set_posture(want):
		_posture_hold = posture_dwell


## The posture to take this tick: a manner of carrying out the leaf, not something Von chooses, so
## it works with the server down. Only a standing body runs, so anything on the move to a
## destination stands, and so does everything outside a fight. Fighting in place (an engaged NPC in
## position, or one holding / reloading while a hostile is known or shots are landing) it crouches:
## a smaller target, and it hides behind cover as high as a crouch. A member of a frag entry holding
## its slot for the burst crouches too (`Entry.holds_crouched`, LD14).
func _wanted_posture() -> StringName:
	if not _evade.is_empty():
		return &"crouch" if _evade_crouches() else &"stand"
	if not posture_enabled or _character.run_input:
		return &"stand"
	if _primitive == &"entry" and _entry.holds_crouched():
		return &"crouch"  # Its slot held for the frag the stack threw into the room (LD14).
	if _primitive == &"ambush" and _arrived:
		return &"crouch"  # Waiting at its post, low (LD15).
	var under_fire: bool = _perception != null and _perception.under_fire()
	if _hostiles.is_empty() and not under_fire:
		return &"stand"
	return &"crouch" if _fights_in_place() else &"stand"


## Whether the running primitive fights where it stands (an engage or a defend in position, a hold,
## a reload), which crouches in a fight; anything else is on its way somewhere, standing.
func _fights_in_place() -> bool:
	match _primitive:
		&"engage", &"defend":
			return _arrived
		&"hold", &"reload":
			return true
	return false


## Whether to sprint this tick, judged after the primitive has steered and the watch stage has
## picked its threat: only while travelling to a destination (a move or engage approach that hasn't
## arrived, a melee closing in; never an ambush, peek, room search, interaction, hold or tactical
## entry — a running character cannot shoot, so an entrant walks with its gun up from the moment it
## heads for the door), when the leaf asks for it (`params.run`) or the NPC is under fire, the
## destination is farther than `run_min_distance`, and a run can be started (stamina
## `run_start_fraction`, or already running). It never sprints with a shot to take or an empty gun
## to reload (a running character can do neither), except a retreat (`params.run_through_fire`),
## which is about leaving the line, not trading shots. The Character spends the stamina and runs
## dry on its own. A follower runs to catch up once it has fallen `follow_step` behind its spot,
## whatever the leaf, and keeps on (`_catching_up`) until it is back within `follow_caught_up` of
## it, through a tick with no step; the gates still drop that run.
func _should_run() -> bool:
	if _catching_up and _character.stamina_fraction() <= 0.0:
		_catching_up = false  # Its stamina ran dry on the last frame's run.
	if not run_enabled or _character.move_input == Vector2.ZERO:
		return false
	var go := _run_now()
	if _primitive == &"follow":
		_catching_up = go
	return go


## `_should_run`'s judgement on a tick the NPC steps: the primitive's destination, the leaf's ask
## or fire, the distance, a shot or reload due and the stamina.
func _run_now() -> bool:
	if not _travelling():
		return false
	var dest := _engage_pos if _primitive == &"melee" else _point
	var near := run_min_distance
	var run: bool = _params.get("run", false)
	var running: bool = _character.is_running()
	if _primitive == &"follow":
		# A follower runs to catch up once it has fallen a place behind its spot, and keeps on
		# until it has caught up: a stop on the way keeps the catch-up, and its next step runs on
		# whatever stamina is left.
		dest = squad.follow_spot(_character)
		near = squad.follow_caught_up if _catching_up else squad.follow_step
		running = _catching_up
		run = true
	if not run and not (_perception != null and _perception.under_fire()):
		return false
	if _character.global_position.distance_to(dest) <= near:
		return false
	if not _threat.is_empty() and not bool(_params.get("run_through_fire", false)) \
			and (_combat.can_fire_at(_threat) or _combat.reload_due()):
		# A shot (or the reload an empty gun needs) is on: a running character can do neither, so
		# walk and take it.
		return false
	return running or _character.stamina_fraction() >= run_start_fraction


## Whether the running primitive is still travelling to a destination it may run to: a move (not a
## room search) or an engage, defend, ambush or follow not yet arrived, or a melee closing in.
func _travelling() -> bool:
	match _primitive:
		&"move":
			return not (_arrived or _look_around)
		&"engage", &"defend", &"ambush", &"follow":
			return not _arrived
		&"melee":
			return true
	return false


## Move: walk to the destination (or into the destination room), aiming as the leaf asks (a threat
## in sight takes the eyes and the gun in the watch stage). A `look_around` move (search / explore)
## walks all the way to the interior point and, on arrival, COVERS the room by sight — turning and
## relocating until it has seen (near-)every sampled point (see `search_coverage.gd`) — before
## flagging the task resolved; any other move stops on arrival and flags resolved at once.
func _apply_move(delta: float) -> void:
	if not _arrived:
		_note_move_arrival()
	if not _arrived:
		_loco.move_to(_point)
	elif not _look_around:
		# Arrived: stand. (The last steering input would walk it on into the wall ahead.)
		_character.move_input = Vector2.ZERO
	else:
		if _coverage.step(delta):  # Look around until the room is covered by sight.
			_look_around = false
			_resolved = true
			var covered: String = _loco.room_key_at(_character.global_position)
			if covered != "":
				_perception.mark_cleared(covered)  # Seen all of it: cleared, as by an entry.
		return
	_aim_move()


## Whether a move still on its way has arrived (in its `arrive_room`, or at its point): a
## `look_around` move then begins covering the room, any other is resolved.
func _note_move_arrival() -> void:
	if _arrive_room != "" and not _look_around:
		_arrived = _loco.room_key_at(_character.global_position) == _arrive_room
	if not _arrived:
		_arrived = _loco.reached(_point)
	if _arrived:
		if _look_around:
			_coverage.begin()
		else:
			_resolved = true


## Where a moving NPC looks when no threat has its eyes (`_apply_watch` puts one there): its target,
## the nearest known threat, the destination, or (default) a few paces down its path, so its view
## cone sweeps the way it is going.
func _aim_move() -> void:
	match _params.get("aim", &"travel"):
		&"target":
			if _engage_id != 0:
				_character.aim_point = _engage_pos
				return
		&"threat":
			if not _hostiles.is_empty():
				_character.aim_point = _hostiles[0]["pos"]
				return
		&"point":
			_character.aim_point = _point
			return
	var ahead: Vector2 = _watch.travel_point()
	if ahead != Vector2.INF:
		_character.aim_point = ahead
	elif _character.move_input != Vector2.ZERO:
		_character.aim_point = _character.global_position + _character.move_input * 100.0


## Engage: walk to the chosen spot (shooting on the way when a line opens), then fight from it —
## peek-and-cover, or an ambush that holds the covered spot and fires the moment a line opens. A
## territorial NPC fighting a contact outside the house stays inside (`_hold_ground`).
func _apply_engage(delta: float) -> void:
	if _engage_id == 0:
		_apply_hold()
		return
	_character.aim_point = _engage_pos  # Aim at where we last saw them, not their true position.
	_hold_ground = _keeps_in(_engage_pos)
	if not _arrived:
		_arrived = _loco.reached(_point)
		if not _arrived:
			_loco.move_to(_point)
			return
		_tactic_timer = tactic_interval  # In position: the tactic gets its full run from here.
		_perception.note_engaged()
	if _params.get("style", &"peek_cover") == &"ambush":
		_combat.ambush(_engage_node, _engage_pos)
		return
	_combat.peek_cover(
		delta,
		_engage_node,
		_engage_pos,
		_hold_ground,
		str(_params.get("confine_room", "")),
	)


## Melee: close to punch range and swing on the fire cooldown (no cover cycle for fists). While
## holding ground it won't chase a contact out of the house — it only swings if one is already in
## reach.
func _apply_melee() -> void:
	if _engage_id == 0:
		_apply_hold()
		return
	_character.aim_point = _engage_pos
	_hold_ground = _keeps_in(_engage_pos)
	_combat.melee(_engage_pos, _hold_ground)


## Whether the fight is held where it is against a contact at `pos`: a member ordered to defend a
## room (`confine_room`, LD8) against one outside that room; a territorial NPC (`confine_inside`)
## against one last seen outside the house.
func _keeps_in(pos: Vector2) -> bool:
	var room := str(_params.get("confine_room", ""))
	if room != "":
		return _loco.room_key_at(pos) != room
	return _params.get("confine_inside", false) and not _engage_inside


## Entry: start the entry on the primitive's first tick, then run its phases (the watch stage shoots
## a threat in sight in every one of them). Done (the room clear, or the entry given up) →
## re-decide.
func _apply_entry(delta: float) -> void:
	_entry.gaze_held = not _threat.is_empty()
	_entry.hostile_in_view = _hostile_in_view()
	if _entry_pending and _begin_pending_entry(delta):
		return
	if _entry.held_back:
		if _detour_first(delta):
			return
		# The way is clear: the entry begins again, from the claims heard meanwhile (others' held
		# back like its own), and its claim goes out.
		_entry.reset()
		if not _entry.begin(_params):
			_finish_entry()
			return
	if _entry.step(delta):
		_finish_entry()
		return
	if _join_over():
		# Its leader's stack went in and cleared the room without it (LD25, D26): it follows again
		# now, not once its entry would have ended. One inside holds the room until its entry ends.
		_join_done = true
		_resolved = true
		_resolve_reason = "join over"
	if _entry.holding_for_go():
		_say_order_step("in_position")  # Ready in its slot and held for the leader's go (LD13).
	if _held and not _entry.throwing():
		# The stun is away (or the bang given up): the decision held off for it is taken now, from
		# where it stands.
		_held = false
		_resolved = true
		_resolve_reason = "after the bang"


## Begin the pending entry on its first tick, once the doorway's slots are laid (or `ROUTE_WAIT` s
## have gone by), and hold an ordered stack's claim back while its way is read. True when the tick
## ends here: still waiting for the slots, or the entry could not begin (and is finished).
func _begin_pending_entry(delta: float) -> bool:
	if not _entry.laid(_params) and _route_wait < ROUTE_WAIT:
		# The doorway's slots are laid once the nav map is baked: a stack claims nothing before.
		_route_wait += delta
		_character.move_input = Vector2.ZERO
		return true
	_entry_pending = false
	_route_wait = 0.0
	if not _entry.begin(_params):
		if StackClaim.is_join(_params):
			# No slot in its leader's stack (a dead end, E20): the join is refused and it follows
			# again (LD24, LD25).
			_perception.end_order(_params.get("order_id"), "refused")
		_finish_entry()
		return true
	_entry.held_back = (_resume.is_empty()
			and _ordered_entry(_params)
			and _entry.phase == "approach")
	return false


## An ordered stack's way to its doorway (D4, LD9), read before the member's claim goes out: its
## entry has begun (its slot, its side and the approach's waypoints are worked out) and holds its
## claim back (`Entry.held_back`) while the whole walk to the slot, leg by leg as the approach walks
## it (`AgentPerception.walk_route`: out of the room being entered and its doorway's view), is read
## for a threshold into a room not cleared (`threshold_ahead`; the room being entered and the
## doorway it stacks at left out), and, with no other recipient coming to the doorway, a doorway
## view it would cross (E15, `passing_ahead`; not one of the room being entered, which the stack
## clears). The first is gone through by entry first, as a detour (`_begin_detour`): the entry is
## dropped unheard, so no claim was made and none is given up; the order's entry starts afresh once
## the detour is over, and reads the way again. True while it is detouring or waits (at most
## `ROUTE_WAIT` s) for a map round the views to be baked; false when the way is clear and the claim
## is due.
func _detour_first(delta: float) -> bool:
	if not entry_guard or _perception.under_fire():
		return false
	var opening: String = _entry.opening
	var into: String = _entry.into
	var entering := "%s>%s" % [opening, into]
	var path := PackedVector2Array()
	var from := Vector2.INF
	var pending := false
	for p: Vector2 in _entry.approach_points():
		var leg: Dictionary = _perception.walk_route(p, entering, from)
		pending = pending or bool(leg["pending"])
		path.append_array(leg["path"])
		from = p
	if pending and _route_wait < ROUTE_WAIT:
		_route_wait += delta
		_character.move_input = Vector2.ZERO
		return true
	var gate := _other_threshold(path, 0, INF)
	if not _entry_recipients_coming():
		var passing: Dictionary = _perception.passing_ahead(path, 0, INF)
		if (not passing.is_empty()
				and passing["opening"] != opening
				and str(passing["into"]) != into
				and (gate.is_empty() or float(passing["dist"]) < float(gate["dist"]))
				and float(_guard_off.get(passing["opening"], -1.0)) <= _guard_clock
				and not _perception.entry_stack(passing["opening"]).claimed()):
			passing["secure"] = true
			gate = passing
	if gate.is_empty():
		return false
	_entry.reset()
	_begin_detour(gate)
	return true


## The threshold into a room not cleared on `path` (from `index`, within `reach` of walking,
## `threshold_ahead`), or {}: not the doorway the entry stacks at, a doorway into the room it
## enters, or one the guard leaves alone for now (`_guard_off`).
func _other_threshold(path: PackedVector2Array, index: int, reach: float) -> Dictionary:
	var gate: Dictionary = _perception.threshold_ahead(path, index, reach)
	if gate.is_empty():
		return gate
	if (gate["opening"] == _entry.opening
			or str(gate["into"]) == _entry.into
			or float(_guard_off.get(gate["opening"], -1.0)) > _guard_clock):
		return {}
	return gate


## Whether the order the pending entry stacks under names another living member: a team is coming to
## the doorway, so nobody leaves the way to it to cover a doorway on the way (E15, as for a stack
## others claim).
func _entry_recipients_coming() -> bool:
	var held: Dictionary = _perception.order()
	if str(held.get("id", "")) != str(_params.get("order_id", "")):
		return false
	return (held.get("to", []) as Array).any(
		func(m): return is_instance_valid(m) and m != _character and m.get("is_dead") != true,
	)


## Whether a hostile stands in view for the entry's purposes (E14): the threat holding the NPC's
## eyes is seen now, or was a moment ago (`watch_lost_gaze` s), and there is a line of fire to it
## from here, so it can be engaged from outside. A hostile remembered from longer ago, or one seen
## but behind a wall or out of range (nothing to engage it with from outside), does not hold an
## entry outside.
func _hostile_in_view() -> bool:
	return (not _threat.is_empty()
			and (bool(_threat["visible"]) or float(_threat["age"]) <= watch_lost_gaze)
			and _combat.has_line_of_fire(_threat))


## The entry is over, or could not start. As the NPC's own order (ENTER) it resolves and the NPC
## re-decides. As a detour (`_begin_detour`) it hands the walk back to the order it paused, which
## carries on from where the entry left the NPC; a doorway whose room is still not cleared (the
## entry did not get to the end) is left alone for `entry_guard_rearm` s.
func _finish_entry() -> void:
	_held = false
	if _resume.is_empty():
		_primitive = &"hold"
		_resolved = true
		return
	if _entry.secured:
		# Secured in passing: not again for a while.
		_guard_off[_entry.opening] = _guard_clock + entry_secure_time
	elif not _perception.is_cleared(_entry.into):
		_guard_off[_entry.opening] = _guard_clock + entry_guard_rearm
	_resume_order()


## Hand the walk back to the order a detour paused.
func _resume_order() -> void:
	var r := _resume
	_resume = {}
	_primitive = r["primitive"]
	_params = r["params"]
	_path = r["path"]
	_labels = r["labels"]
	_point = r["point"]
	_arrived = r["arrived"]
	_look_around = r["look_around"]
	_arrive_room = r["arrive_room"]
	_act_armed = r["act_armed"]
	_entry_pending = bool(r.get("entry_pending", false))
	# The order's cap runs from here: the entry took the time it took.
	_commit_timer = max_commit_time
	if _primitive == &"throw":
		_begin_throw_order()  # The walk to the throw spot goes on from where the entry left it.


## The entry guard (E9): a walk that is about to cross into a room that is not cleared goes in by
## tactical entry, whatever order it came from (a search or explore, a lead, a closing-in, the way
## to an object or to a throw spot, the front entrance). It reads the walk the nav agent was just
## given rather than the leaf's destination, so a path through an intermediate room, a reposition in
## a fight and the way to a doorway itself are all covered. Exempt: a retreat (`entry_guard: false`
## on its node), an NPC under fire (but for a walk into the room the shots came from,
## `_into_the_shots`), an entry already running, and anything that is not walking.
func _entry_guard() -> void:
	if _primitive == &"entry":
		_guard_running_entry()
		return
	if not _walk_guarded():
		return
	var walk: Dictionary = _loco.path_ahead()
	if walk.is_empty():
		return
	var gate: Dictionary = _perception.threshold_ahead(
		walk["path"], walk["index"], entry_guard_range,
	)
	if not _perception.under_fire():
		var passing := _passing_gate(walk, gate)
		if not passing.is_empty():
			gate = passing
	elif gate.is_empty() or not _into_the_shots(str(gate["into"])):
		# Under fire: no time to stack or to secure what it passes, but for a walk into the room the
		# shots came from.
		return
	if gate.is_empty() or float(_guard_off.get(gate["opening"], -1.0)) > _guard_clock:
		return
	_begin_detour(gate)


## The entry guard over a running entry: a detour's entry shot at before it crossed is given up (but
## into the shots it stacks), and an ENTER order's own approach is guarded (`_guard_approach`).
func _guard_running_entry() -> void:
	if (not _resume.is_empty()
			and not _entry.committed()
			and _perception.under_fire()
			and not _into_the_shots(_entry.into)):
		# Shot at before it crossed: no time to stack. (Once crossing it finishes the crossing; into
		# the shots it stacks.)
		_cancel_detour()
	elif _resume.is_empty() and not _entry_pending and _entry.phase == "approach":
		_guard_approach()


## Whether the running primitive (not an entry) is on a walk the entry guard covers this tick: the
## guard on, the NPC stepping, a move, defend or ambush not yet arrived, an engage, an interaction
## or a throw's walk to its throw spot, and not a retreat (`entry_guard: false`).
func _walk_guarded() -> bool:
	if not entry_guard or _perception == null or not _perception.entry_enabled:
		return false
	match _primitive:
		&"move", &"defend", &"ambush":
			if _arrived:
				return false  # Holding at the destination, or covering the room by sight.
		&"engage", &"interact":
			pass
		&"throw":
			if _combat.throw_stage != "walk":
				return false  # Throwing where it stands: no walk to guard.
		_:
			return false
	return not ((_character.move_input as Vector2).length() < 0.1
			or not bool(_params.get("entry_guard", true)))


## An ENTER order's own walk to its stack (E15): a doorway it goes past on the way (in a corridor,
## not the one it is stacking at) is secured first like any other walk's. The entry pauses (it told
## the stack it gave its claim up and starts again afterwards). Not for a member heading for a stack
## that others have claimed, or that its order names others for: the team goes to its door as one,
## and a member that left it to cover a door on the way would leave the point to go in alone. (An
## ordered stack reads its whole way for both before it claims, `_detour_first`; this catches what
## comes up on the walk.) An ordered stack's walk (`docs/leadership.md` LD9, D4), whatever
## `entry_enabled` says, also goes into a room that is not cleared on its way by entry first, as any
## walk does (E9), team or none, and its entry starts afresh after it.
func _guard_approach() -> void:
	var ordered := _ordered_entry(_params)
	if (not entry_guard
			or not (_perception.entry_enabled or ordered)
			or (_character.move_input as Vector2).length() < 0.1
			or _perception.under_fire()):
		return
	var walk: Dictionary = _loco.path_ahead()
	if walk.is_empty():
		return
	var gate := {}
	if ordered:
		gate = _other_threshold(walk["path"], walk["index"], entry_guard_range)
	var team_coming: bool = (_perception.entry_stack(_entry.opening).claimed()
			or (ordered and _entry_recipients_coming()))
	var passing := {} if team_coming else _passing_gate(walk, gate)
	if (not passing.is_empty()
			and passing["opening"] != _entry.opening
			and str(passing["into"]) != _entry.into):
		gate = passing
	if gate.is_empty():
		return
	_entry.abandon()
	_begin_detour(gate)


## The doorway the walk goes past before it reaches `gate` (the doorway it crosses, {} for none), as
## a gate to secure (E15), or {}: one in a room not cleared, nearer along the walk than the
## crossing, that no teammate is working (an ally on its radio is entering it) and that was not just
## secured or given up.
func _passing_gate(walk: Dictionary, gate: Dictionary) -> Dictionary:
	var passing: Dictionary = _perception.passing_ahead(
		walk["path"], walk["index"], entry_guard_range,
	)
	if (passing.is_empty()
			or (not gate.is_empty() and float(passing["dist"]) >= float(gate["dist"]))):
		return {}
	if (float(_guard_off.get(passing["opening"], -1.0)) > _guard_clock
			or _perception.entry_stack(passing["opening"]).claimed()):
		return {}
	passing["secure"] = true
	return passing


## Pause the running order and go through doorway `gate` (`{ opening, into }`) by tactical entry
## first. The order is kept whole in `_resume` and comes back when the entry ends (`_finish_entry`).
## A new decision replaces it and lets the entry carry on (`set_leaf`), unless it is one the guard
## does not apply to: then the detour is dropped (`_drop_detour`). Into a room the NPC suspects (the
## shots' room among them), the entry is a bang one when the stack carries a stun (E17,
## `Entry.begin`).
func _begin_detour(gate: Dictionary) -> void:
	_stash_order()
	_primitive = &"entry"
	_params = {
		"opening": gate["opening"],
		"into": gate["into"],
		"secure": bool(gate.get("secure", false)),
	}
	_entry_pending = true


## Give a detour's entry up (the stack is told) and carry on with the paused order, which walks
## straight through.
func _cancel_detour() -> void:
	_guard_off[str(_params.get("opening", _entry.opening))] = _guard_clock + entry_guard_rearm
	_entry_pending = false
	_entry.abandon()
	_resume_order()


## Keep the running order whole in `_resume`, to come back when the entry ends.
func _stash_order() -> void:
	_resume = {
		"primitive": _primitive, "params": _params, "path": _path, "labels": _labels,
		"point": _point, "arrived": _arrived, "look_around": _look_around,
		"arrive_room": _arrive_room, "act_armed": _act_armed,
		# An ENTER order that is paused starts afresh when it comes back.
		"entry_pending": _primitive == &"entry",
	}


## A new decision (or no decision to be had) ends a detour: the paused order is gone, and the
## doorway it was stacking at is left alone for `entry_guard_rearm` s so a fight that cut the entry
## short does not restart it every decision.
func _drop_detour() -> void:
	if _resume.is_empty():
		return
	_guard_off[str(_params.get("opening", _entry.opening))] = _guard_clock + entry_guard_rearm
	_resume = {}


## Interact: walk to the chosen object facing it (or a known hostile, to keep eyes on them); once
## its action is in reach, face it, run it and hold the interaction. Ends (and re-decides) if the
## object is gone or the action can't start.
func _apply_interact() -> void:
	if _target_obj == null or not is_instance_valid(_target_obj):
		_primitive = &"hold"
		_resolved = true
		_character.move_input = Vector2.ZERO
		return
	if not _interaction_in_reach():
		_character.aim_point = (_hostiles[0]["pos"]
				if not _hostiles.is_empty()
				else _target_obj.global_position)
		_loco.move_to(_target_obj.global_position)
		return
	_character.move_input = Vector2.ZERO
	_character.aim_point = _target_obj.global_position  # face the object to perform the interaction
	if not _act_armed:
		_act_armed = true  # Let facing settle before acting.
		return
	if _character.interact_with(_target_obj, _interact_id):
		_in_interaction = true
		_interaction_timer = interaction_dwell
	else:
		_primitive = &"hold"
		_resolved = true


## Throw (docs/grenades.md G17): with a throw spot (`params.walk`), walk there first, the gun in
## hand and the watch stage on a threat; then take the grenade in hand, aim at the spot and throw it
## (`Combat.throw_step`), radio it as it leaves the hand, then stand with the gun back in hand until
## the grenade has gone off. The evade reflex carries the thrower off if the burst reaches it (it
## replaces this order); one the burst does not reach has nothing more to do. Then the NPC
## re-decides. A throw that cannot be made (the lob is blocked now, none left, the hand never free)
## is given up at once and the NPC re-decides. A thrower that has drifted a few px out of range
## since the spot was offered closes in on it (`Combat.throw_step`) instead; once the wind-up has
## begun the throw is committed, standing where it is.
func _apply_throw(delta: float) -> void:
	if _combat.throw_stage != "away":
		var blocked: bool = (_combat.throw_stage == "aim"
				and not _perception.throw_clear(_character.global_position, _throw_spot))
		if blocked or _combat.throw_step(delta) == &"failed":
			_end_throw()
		return
	_character.move_input = Vector2.ZERO
	if _throw_wait < 0.0:
		_end_throw()
		return
	_throw_wait -= delta
	var live: bool = _perception.known_grenades().any(func(g): return g["source"] == &"own")
	_throw_seen = _throw_seen or live
	if (_throw_seen and not live) or _throw_wait <= 0.0:
		_end_throw()


## Called every tick before the evade reflex is handed its plan: whether the grenade being thrown
## has left the hand (the end of the wind-up). Then it is radioed, and the wait for the burst
## begins. This has to come first: a grenade just thrown is a live one the thrower may be inside the
## zone of, and the evade replaces the throw order the same tick. A frag entry's thrower (LD14)
## radios its frag the same way, the tick after it left the hand (`Entry.take_thrown`).
func poll_throw() -> void:
	if _primitive == &"throw" and _combat.throw_released():
		_throw_calls.append({ "kind": _throw_kind, "point": _throw_spot })
		_throw_wait = _perception.grenade_fuse(_throw_kind) + THROW_WAIT_MARGIN
	elif _primitive == &"entry":
		var thrown: Dictionary = _entry.take_thrown()
		if not thrown.is_empty():
			_throw_calls.append(thrown)  # A frag entry's frag (LD14), radioed as any thrown frag.


## The throw is over (the burst, or it could not be made): the NPC re-decides.
func _end_throw() -> void:
	_combat.end_throw()
	_primitive = &"hold"
	_throw_wait = -1.0
	_resolved = true


## The throws to radio since the last call, `{ kind, point }`: the controller posts each as a
## `frag_out` / `bang_out` callout.
func take_throw_calls() -> Array:
	var out := _throw_calls
	_throw_calls = []
	return out


## Read-only: the throw the NPC is about to make, `{ from, to, kind, radius }` (empty once it has
## left the hand, or when the NPC is not throwing), for the grenade overlay.
func throw_plan() -> Dictionary:
	if _primitive != &"throw" or _combat.throw_stage == "away":
		return {}
	var from: Vector2 = (_params.get("from", _character.global_position)
			if _combat.throw_stage == "walk"
			else _character.global_position)
	return {
		"from": from,
		"to": _throw_spot,
		"kind": _throw_kind,
		"radius": float(_params.get("radius", 0.0)),
	}


## Defend (LD8): walk to the defend spot (a guarded walk where the entry guard applies, as any
## walk), then hold it, still; the watch stage keeps the gun on its doorway, or turns it among the
## room's doorways, and on a threat in sight. Pushed off the spot, it walks back. It says
## `in_position` on the radio once there. An empty gun is reloaded meanwhile, as in a hold. An
## ambush (LD15) is the same walk and hold at its post, crouched, its gun on the threshold.
func _apply_defend() -> void:
	if _arrived and _character.global_position.distance_to(_point) > DEFEND_DRIFT:
		_arrived = false
	if not _arrived:
		_arrived = _loco.reached(_point, DEFEND_REACH)
		if _arrived:
			_say_order_step("in_position")
	if not _arrived:
		_loco.move_to(_point, DEFEND_REACH)
		_aim_move()
		return
	_character.move_input = Vector2.ZERO
	_combat.reload_if_dry()


## Whether the order the running leaf carries out (its `order_id`) is still the NPC's live order
## (`AgentPerception.order`).
func _order_live() -> bool:
	return (_params.has("order_id")
			and str(_perception.order().get("id", "")) == str(_params["order_id"]))


## Note step `step` of the order the running leaf carries out (its `order_id`), once until the next
## step differs, for the controller to radio (`take_order_steps`, `docs/leadership.md` LD7). Nothing
## for a leaf that is no order.
func _say_order_step(step: String) -> void:
	if not _params.has("order_id"):
		return
	var id = _params["order_id"]
	if str(_order_said.get("id", "")) == str(id) and _order_said.get("step", "") == step:
		return
	_order_said = { "id": id, "step": step }
	_order_steps.append({ "order_id": id, "step": step })


## The order steps to radio since the last call (`{ order_id, step }`).
func take_order_steps() -> Array:
	var out := _order_steps
	_order_steps = []
	return out


## Follow (LD20 to LD22): keep to the spot the squad gives the NPC (`Squad.follow_spot`). The walk
## is re-aimed only once that spot has moved `follow_retarget` from where it is going, and is over
## within `follow_arrive` of it or where its path ends short of one it cannot reach; a follower
## catching up (`_catching_up`) whose walk target lagged its live spot re-aims at that spot there,
## until it is within `follow_caught_up` of it. Its walk over, its catch-up is over too.
## There it stands facing away from its leader (the leash's centre, its live position) and, at rest
## with nothing to fight, tops up a low magazine. The watch stage shoots what it sees on the way.
## Its spot gone (it leads now, or left the squad): re-decide.
func _apply_follow() -> void:
	var spot: Vector2 = (squad.follow_spot(_character)
			if squad != null and is_instance_valid(squad)
			else Vector2.INF)
	if spot == Vector2.INF:
		_character.move_input = Vector2.ZERO
		_primitive = &"hold"
		_resolved = true
		return
	if _follow_to == Vector2.INF or spot.distance_to(_follow_to) > squad.follow_retarget:
		_follow_to = spot
		_arrived = false
	if not _arrived:
		_arrived = _loco.reached(_follow_to, squad.follow_arrive)
		if (_arrived and _catching_up
				and _follow_to.distance_to(spot) > squad.follow_arrive
				and _character.global_position.distance_to(spot) > squad.follow_caught_up):
			# Catching up, it is not there until it has caught up: on to its live spot.
			_follow_to = spot
			_arrived = false
		_follow_stood = GameClock.seconds()
	if not _arrived:
		_loco.move_to(_follow_to, squad.follow_arrive)
		_aim_move()
		return
	_catching_up = false
	_character.move_input = Vector2.ZERO
	var here: Vector2 = _character.global_position
	var lead: Vector2 = _combat.leash_center
	if lead != Vector2.INF and here.distance_to(lead) > 1.0:
		_character.aim_point = here + (here - lead).normalized() * 100.0
	# At rest once it has stood as long as a still leader does (a file walk stops between re-aims).
	if (GameClock.seconds() - _follow_stood >= squad.follow_still_time
			and _threat.is_empty()
			and not _perception.under_fire()
			and _combat.magazine_low(low_ammo_fraction)):
		_combat.top_off()


## The leash the NPC fights within (LD23), set every tick by the controller: `radius` px of
## `center`, its leader's live position (`Vector2.INF`: none, it does not follow).
func set_leash(center: Vector2, radius: float) -> void:
	_combat.leash_center = center
	_combat.leash = radius


## Whether the running primitive is on its way somewhere it chose: a move or an engage not yet
## there, or a throw's walk to its throw spot.
func walk_pending() -> bool:
	match _primitive:
		&"move", &"engage":
			return not _arrived
		&"throw":
			return _combat.throw_stage == "walk"
	return false


## Hold: stand still. Where it looks is the watch stage's (`_apply_watch`): a threat if one has its
## eyes, else the doors. An empty gun is reloaded meanwhile, so a steady NPC (no decision to be had)
## isn't left unarmed.
func _apply_hold() -> void:
	_character.move_input = Vector2.ZERO
	_combat.reload_if_dry()


## Reload: stand and swap magazines, its eyes where the watch stage puts them (a threat, else the
## doors); when the reload ends (or can't start) the task is resolved and the NPC re-decides. A
## reload refused while the previous leaf's run is still winding down is retried the next tick.
func _apply_reload() -> void:
	_character.move_input = Vector2.ZERO
	if _character.ammo.is_reloading():
		_reload_started = true
		return
	if not _reload_started:
		var gun: int = _character.gun_slot()
		if gun >= 0:
			_character.select_slot(gun)
		_character.ammo.reload()
		if _character.ammo.is_reloading():
			_reload_started = true
			return
		if _character.is_running():
			return
	_primitive = &"hold"
	_resolved = true


# --- The evade reflex (G16) -------------------------------------------------------------------


## Whether the NPC is running from, or holding out of the way of, a live grenade.
func evading() -> bool:
	return not _evade.is_empty()


## The safe spot the evade runs to (`Vector2.INF` when none: not evading, or no spot to reach in
## time).
func evade_spot() -> Vector2:
	return _evade.get("spot", Vector2.INF)


## Whether the NPC fires blind while this blinding lasts (`docs/grenades.md` G15): the controller's
## roll, handed in the tick it goes blind. False: it holds its fire (no gun round, no burst carried
## on) until it can see.
func set_blind_fire(on: bool) -> void:
	_combat.blind_fire = on


## Take the perception's plan to get clear of a live grenade (`{}`: nothing threatens the NPC),
## every tick. It takes priority over every primitive, committed or not: the order running is given
## up (an entry in progress too, the stack is told) and the NPC runs for the plan's spot. The plan
## stands while the grenade lives, so the NPC holds its spot to the burst; when the plan ends the
## NPC re-decides. One wait: the NPC's own grenade in the wind-up cannot be called back and leaves
## the hand at most a wind-up (0.3 s) later, toward where it is aimed; turning away for the evade
## meanwhile would throw it the wrong way. The evade starts the tick it leaves the hand
## (`poll_throw` runs first).
func set_evade(plan: Dictionary) -> void:
	if plan.is_empty():
		if not _evade.is_empty():
			_evade = {}
			_resolved = true
		return
	if _evade.is_empty() and _primitive == &"throw" and _combat.throw_stage == "windup":
		# Its own grenade is about to leave the hand, toward the spot: thrown first, then the run.
		return
	if _evade.is_empty() and _primitive == &"entry" and _entry.expects_burst(plan):
		# The stun (or frag, its slot out of the zone) a bang entry threw into its room: the stack
		# holds turned away from the door for it already.
		return
	if _evade.is_empty():
		_drop_detour()
		_entry_pending = false
		_entry.abandon()
		_evade_arrived = false
		_primitive = &"hold"
		_params = {}
		_path = ["evade"]
		_labels = ["EVADE", "a live %s grenade" % plan.get("kind", "")]
		_leaf_ms = GameClock.msec()
		_target_obj = null
	elif (plan["spot"] as Vector2) != (_evade["spot"] as Vector2):
		_evade_arrived = false  # A new spot (the grenade moved): run to that one.
	_evade = plan


## Whether the evade crouches the NPC: it is behind cover that shields a crouched body only, or it
## is caught in the open by a frag with no way out (a smaller target, at least).
func _evade_crouches() -> bool:
	if evade_spot() == Vector2.INF:
		return _evade.get("kind") == &"frag"
	return _evade_arrived and bool(_evade.get("crouch", false))


## Carry the evade out: run to the spot (its back to the grenade, looking away from it all the way),
## then hold it, crouched when the spot is cover. With no spot to reach in time it stays and turns
## its back (a stun's flash then blinds it for the back-turned share only).
func _apply_evade(delta: float) -> void:
	if _character.is_busy():
		# Up off the chair: a grenade outranks what it was doing, whoever started it.
		_character.end_interaction()
		_in_interaction = false
	_threat = {}
	_gaze = "evade"
	var spot: Vector2 = evade_spot()
	var here: Vector2 = _character.global_position
	var away: Vector2 = here - (_evade["point"] as Vector2)
	away = away.normalized() if away.length() > 1.0 else -(_character.facing as Vector2)
	var running := false
	if spot != Vector2.INF:
		if not _evade_arrived:
			_evade_arrived = _loco.reached(spot, EVADE_REACH)
		if not _evade_arrived:
			_loco.move_to(spot, EVADE_REACH)
			running = _evade_runs()
	if spot == Vector2.INF or _evade_arrived:
		_character.move_input = Vector2.ZERO
	# Its back to the burst all the way, running or holding: a flash blinds the face.
	_character.aim_point = here + away * 100.0
	_character.run_input = running
	_guard_clock += delta
	_apply_posture(delta)
	_running = _character.is_running()
	_posture = _character.posture()
	_reloading = _character.ammo.is_reloading()


## Whether the evade runs to its spot: running is on and a run can go on or start (stamina
## `run_start_fraction`).
func _evade_runs() -> bool:
	return (run_enabled
			and (_character.is_running() or _character.stamina_fraction() >= run_start_fraction))


# --- Helpers ---------------------------------------------------------------------------------


## Whether the chosen interaction on `_target_obj` is currently reachable (lets the approach stop
## and the action begin).
func _interaction_in_reach() -> bool:
	for entry in _character.interactions_in_reach():
		if entry["object"] != _target_obj:
			continue
		for spec in entry["specs"]:
			if spec.get("id", "") == _interact_id:
				return true
	return false
