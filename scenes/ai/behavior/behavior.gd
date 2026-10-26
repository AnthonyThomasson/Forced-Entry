extends Node
## AI BEHAVIOUR sub-domain. Runs the LEAF the decision planner chose — one behaviour PRIMITIVE with
## its params — as concrete movement and actions on the character, and holds the System-Two state
## Von (a stateless single-shot ranker) lacks: the engaged contact, the peek-and-cover combat cycle,
## the interaction in progress, and the COMMITMENT that keeps a choice running until it completes or
## a re-decision is due. The primitives: move     — go to `point` (or until entering `arrive_room`),
## aiming along the way (`aim`: travel / target / threat / point); a `look_around` search move
## covers the room by sight (`search_coverage.gd`): it turns and relocates until it has seen all of
## it. engage   — go to `point`, then fight `target_id` from there: `peek_cover` (step out, shoot,
## duck) or `ambush` (hold the covered spot, fire the moment a line opens). melee    — close on
## `target_id` and punch. interact — walk to `object`, run its interaction `id`, hold it for
## `tuning.decision.interaction_dwell`. reload — stand and swap in a fresh magazine
## (`Character.ammo.reload()`),
## then re-decide. entry    — go through doorway `opening` into room `into` as a team member or
## alone: stack, slice the pie, cross without stopping, take a corner, clear the room (`entry.gd`).
## throw    — walk to the throw spot `from` when it has one (`walk`), take a grenade in hand, aim at
## `point`, throw it, radio it and wait out the fuse with the gun back in hand (`combat.gd`; the
## GRENADE tactic, `docs/grenades.md` G17). defend   — the order to defend `room`
## (`docs/leadership.md` LD8): walk to the defend `spot`, then hold it with the gun on its doorway
## `door_pos` (or, with none, turning among the room's doorways), as long as the order stands.
## follow   — keep to the spot its squad gives it (`Squad.follow_spot`): walk there, stand there
## facing away from its leader, top up a low magazine at rest (`docs/leadership.md` LD20 to LD22).
## hold     — stay and watch. Outside the primitives, **the evade reflex** (`grenades.set_evade`,
## `docs/grenades.md` G16) takes over the NPC whatever it is doing, an entry included, while a live
## grenade threatens it: it runs to the safe spot the perception found, crouches there if it is
## behind cover, holds facing away until the burst, and re-decides. Whatever the primitive, a final
## WATCH stage (`watch.gd`, `docs/gaze-and-fire.md`) puts a threat in sight under the NPC's eyes and
## gun and, with none, makes it look down its path or at its doors. It never chooses WHAT to do —
## the planner does — and applies no policy beyond the params it is handed (`confine_inside` keeps a
## territorial NPC from chasing out of the house). It owns a `Locomotion` child for all pathing, a
## `Combat` module (shots, punches, bursts, the peek-and-cover cycle) and a `SearchCoverage` module,
## reads the world only through the PERCEPTION sub-domain (known contacts, combat geometry,
## engagement memory) and drives the character only through its public controller contract
## (`movement.move_input` / `movement.aim_point`, `inventory.select_slot`, `weapon.shoot`,
## `weapon.melee`, `use.interact_with`, `use.end_interaction`). Every tunable is read live from the
## NPC's tuning (`NpcTuning`, handed in by `setup`), by the behaviour and by each of its modules;
## `apply_config(npc_squad)` hands in the side's squad.

const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")
const Combat := preload("res://scenes/ai/behavior/combat.gd")
const SearchCoverage := preload("res://scenes/ai/behavior/search_coverage.gd")
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const RunningLeaf := preload("res://scenes/ai/behavior/running_leaf.gd")
const Watch := preload("res://scenes/ai/behavior/watch.gd")
## The parts (`fight`, `errand`, `gait`, `grenades`, `orders`).
const Fight := preload("res://scenes/ai/behavior/behavior_fight.gd")
const Errand := preload("res://scenes/ai/behavior/behavior_errand.gd")
const Gait := preload("res://scenes/ai/behavior/behavior_gait.gd")
const Grenades := preload("res://scenes/ai/behavior/behavior_grenades.gd")
const Orders := preload("res://scenes/ai/behavior/behavior_orders.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
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

## The NPC's tunables (its topic nodes, `NpcTuning`), handed in by `setup`: the behaviour and its
## modules read them live (`tuning.decision.max_commit_time`, `tuning.pace.run_enabled`, ...).
var tuning: NpcTuning
## The running leaf: its primitive, params, path and labels, destination and arrival, commitment and
## tactic clocks, and whether it is resolved; see running_leaf.gd.
var task := RunningLeaf.new()
## The fight: the hostiles known, the contact fought, the engage, melee and reload primitives; see
## behavior_fight.gd.
var fight: Fight
## The errands: the move, interact and hold primitives, a search's room coverage and what a walk
## accounts for; see behavior_errand.gd.
var errand: Errand
## The gait: running and the posture; see behavior_gait.gd.
var gait: Gait
## The grenades: the throw primitive and the evade reflex; see behavior_grenades.gd.
var grenades: Grenades
## The orders: the squad, the defend, ambush and follow primitives, the order steps, an ordered
## stack and the leash; see behavior_orders.gd.
var orders: Orders
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
## Shots, punches, bursts and the peek-and-cover cycle; see combat.gd.
var _combat: RefCounted
## A tactical entry through a doorway; see entry.gd.
var _entry: RefCounted
## The threat that takes the eyes and the doors a resting NPC watches; see watch.gd.
var _watch: RefCounted
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
## The running join's end has been said (`orders.join_over`, LD25).
var _join_done := false


## Build the Locomotion child and capture the perception sub-domain and the NPC's `npc_tuning`. The
## controller calls this once in its _ready(); it then calls apply_config(), which hands in the
## side's squad (here and again each decision).
func setup(perception: Node, nav_agent: NavigationAgent2D, npc_tuning: NpcTuning) -> void:
	_perception = perception
	tuning = npc_tuning
	fight = Fight.new(self)
	errand = Errand.new(self)
	gait = Gait.new(self)
	grenades = Grenades.new(self)
	orders = Orders.new(self)
	_loco = Locomotion.new()
	_loco.setup(nav_agent, tuning)
	_loco.rooms = rooms
	_loco.doors.views = perception
	add_child(_loco)
	errand.coverage = SearchCoverage.new()
	errand.coverage.setup(_loco, perception, tuning)
	_combat = Combat.new()
	_combat.setup(_loco, perception, tuning)
	_combat.dry.connect(fight.on_dry)
	_watch = Watch.new()
	_watch.setup(_loco, perception, tuning)
	_entry = Entry.new()
	_entry.world.tuning = tuning
	_entry.setup(_loco, perception, errand.coverage, _watch, _combat)


## Hand in the NPC's body, which the behaviour and its modules drive from then on. The controller
## calls this once it knows which character it drives.
func bind(character: Node) -> void:
	_character = character
	_loco.bind(character)
	errand.coverage.bind(character)
	_watch.bind(character)
	_combat.bind(character)
	_entry.bind(character)


## Hand in its side's `squad`, to the behaviour and its entry module; they and the other modules
## read `tuning`, the NPC's topic nodes (the one authoring surface), live. Idempotent, so the
## controller may call it each decision.
func apply_config(npc_squad: Node = null) -> void:
	orders.squad = npc_squad
	_entry.world.squad = npc_squad


# --- Read-only views -------------------------------------------------------------------------


## Read-only: the decision path the NPC is carrying out, as ids ("combat/t_12/flank/side_left").
func current_act() -> String:
	return "/".join(task.path) if not task.path.is_empty() else "hold"


## Read-only: the decision path as labels, joined ("SEARCH - ENTER - the doorway into the kitchen").
func path_label() -> String:
	return " - ".join(task.labels)


## Read-only: the running order's decision path, as ids and as labels (`{ path, labels }`).
func order() -> Dictionary:
	return { "path": task.path.duplicate(), "labels": task.labels.duplicate() }


## Whether the running entry turned from quiet to a bang since the last call (E17, a late reason):
## true once.
func take_entry_turned() -> bool:
	return task.primitive == &"entry" and _entry.take_turned()


## Re-adopt the running entry order as a bang entry under `path` and `labels` (an ENTER turned STUN
## ENTRY): the entry runs on where it is, only what it is called and its `bang` param change.
func adopt_bang(path: Array, labels: Array) -> void:
	task.path = path
	task.labels = labels
	task.params["bang"] = true


## Read-only: the broad mode of the running leaf (combat / investigate / search / idle / hold).
func _intent() -> String:
	return str(task.path[0]) if not task.path.is_empty() else "hold"


## Read-only: whether the NPC is fighting (so a fresh hit doesn't force a re-decision).
func in_combat() -> bool:
	return _intent() == "combat"


## Read-only: whether the running choice is still in progress (en route, fighting, using an object)
## rather than finished (arrived, holding) — the planner only offers "keep your current plan" for
## one still in progress.
func ongoing() -> bool:
	match task.primitive:
		&"move":
			return not task.arrived
		&"engage", &"melee", &"interact", &"throw", &"defend", &"ambush", &"follow":
			return true
		&"reload":
			return fight.reloading
		&"entry":
			return _entry_pending or _entry.state.phase not in ["", "done"]
	return false


## Read-only: the engaged contact's last-seen inside/outside state packed into the salient key — the
## controller re-decides when this (or the known-hostile set) changes. A throw order keeps its
## target in the key after the contact ages out (`grenades.throw_target`), so the lapse is no
## change: the throw goes on to the spot it was offered on (G17). A target that died leaves the key,
## so the NPC re-decides.
func salient_key() -> String:
	var ids: Array = fight.hostiles.map(func(c): return c["id"])
	var engaged := fight.engage_id != 0
	var held := grenades.throw_target()
	if held != 0 and not ids.has(held):
		ids.append(held)
		engaged = true  # `fight.engage_inside` keeps the lost contact's last-seen state.
	ids.sort()
	return "%s|%s" % [str(ids), str(fight.engage_inside) if engaged else "-"]


## Read-only: the FULL decision path the NPC is carrying out, every level from the broad mode down
## to the concrete option ("COMBAT - Intruder - FLANK - their left side (kitchen)"), then where it
## is in carrying it out — for debug overlays and the HUD.
func debug_status() -> String:
	var line: String = " - ".join(task.labels) if not task.labels.is_empty() else "HOLD"
	var state := _progress()
	if state != "":
		line += "  · " + state
	if gait.posture != &"stand":
		line += "  · " + "crouching"
	if _perception != null and _perception.under_fire():
		line += "  ⚠ under fire"
	return line


## Read-only: what the NPC is doing, for Von's "current activity" line: the full path, its progress
## and how long it has been at it.
func activity_text() -> String:
	if task.labels.is_empty():
		return ""
	var secs := int((GameClock.msec() - task.leaf_ms) / 1000.0)
	return "%s (%s, for %ds)" % [" - ".join(task.labels), _progress(), secs]


## Where the running primitive stands ("en route", "in position, ducking behind cover", …).
func _progress() -> String:
	match task.primitive:
		&"move", &"melee", &"interact", &"reload":
			return errand.walk_progress()
		&"engage":
			return fight.engage_progress()
		&"entry":
			return ENTRY_PROGRESS.get(_entry.state.phase, "heading for the door")
		&"throw":
			return grenades.throw_progress()
		&"defend", &"ambush", &"follow":
			return orders.post_progress()
	return "waiting" if not task.labels.is_empty() else ""


## Read-only: the full primitive/engagement/commitment state as structured data, for the
## controller's `debug_state()` snapshot. Built from live state (never mutates); JSON-safe.
func debug_state() -> Dictionary:
	return {
		"act": current_act(),
		"labels": " - ".join(task.labels),
		"primitive": String(task.primitive),
		"params": _json_safe(task.params),
		"arrived": task.arrived,
		"running": gait.running,
		"posture": String(gait.posture),
		"reloading": fight.reloading,
		"engage": str(fight.engage_node.name) if is_instance_valid(fight.engage_node) else "",
		"engage_id": fight.engage_id,
		"engage_inside": fight.engage_inside,
		"combat_phase": _combat.phase,
		"holds_fire": _combat.holds_fire() if _character != null else false,
		"hold_ground": fight.hold_ground,
		"hostiles_known": fight.hostiles.size(),
		"gaze": {
			"mode": _watch.gaze,
			"threat": str(_watch.threat["node"].name)
				if not _watch.threat.is_empty() and is_instance_valid(_watch.threat["node"])
				else "",
		},
		"in_interaction": errand.in_interaction,
		"evade": _json_safe(grenades.evade) if not grenades.evade.is_empty() else {},
		"timers": {
			"commit": task.commit_timer,
			"tactic": task.tactic_timer,
			"interaction": errand.interaction_timer,
			"fire": _combat.fire_timer,
			"cover": _combat.cover_timer,
			"combat_dest": _combat.dest_timer,
		},
		"entry": _json_safe(debug_entry()),
		"loco": _loco.debug_state(),
		"order": orders.order_leaf(),
	}


## Read-only: the running tactical entry (doorway, slot, side, phase, what the pie saw, the corner),
## or {} when the NPC isn't entering. See entry.gd `debug()`.
func debug_entry() -> Dictionary:
	return _entry.debug() if task.primitive == &"entry" else {}


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
		"detour": task.primitive == &"entry" and not _resume.is_empty(),
		"resume_point": _resume.get("point", Vector2.INF),
		"resume_label": " - ".join(_resume.get("labels", [])),
		"rearm": [],
		"range": tuning.entry_guard.reach,
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
		var walk: Dictionary = _loco.path_ahead() if task.primitive != &"entry" else {}
		if not walk.is_empty():
			var gate: Dictionary = _perception.threshold_ahead(
				walk["path"], walk["index"], GUARD_PREVIEW_RANGE,
			)
			if not gate.is_empty():
				var geo: Dictionary = _perception.entry_geometry(gate["opening"], gate["into"])
				if not geo.is_empty():
					gate["pos"] = geo["pos"]
					guard["ahead"] = gate
	return { "entry": _entry.debug_view() if task.primitive == &"entry" else {}, "guard": guard }


## Whether the NPC is committed: crossing a doorway, or with its arm drawn back to throw (a grenade
## cannot be called back). The controller holds every re-decision until it is through.
func committed() -> bool:
	return ((task.primitive == &"entry" and _entry.committed())
			or (task.primitive == &"throw" and _combat.throw.stage == "windup"))


## The entry steps to radio since the last call (claims in `StackClaim`'s fields), with the
## doorway, the room it leads into, slot and side they are about; the controller posts them as
## callouts.
func take_entry_calls() -> Array:
	var out: Array = []
	for c in _entry.take_calls():
		c.merge({
			"opening": _entry.state.opening,
			"into": _entry.state.into,
			"slot": _entry.state.slot,
			"side": _entry.state.side,
		})
		out.append(c)
	return out


## Read-only: the movement-progress sample (seconds stalled, recent trail) for the stuck overlay.
func debug_progress() -> Dictionary:
	return _loco.stall.debug_progress()


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
	orders.awaiting = false
	if not grenades.evade.is_empty():
		# Running from a grenade: a decision that was in flight is stale by the burst, which ends in
		# a new one.
		return
	if committed() and _resume.is_empty():
		# Crossing a doorway on its own ENTER, throwing the bang, or winding up a throw: a decision
		# that was in flight waits (it ends in a re-decision). The bang's thrower (E17) throws
		# first, then decides again from where it stands (`_apply_entry`).
		task.held = task.held or (task.primitive == &"entry" and _entry.throwing())
		return
	if orders.same(leaf):
		# The ordered stack it is carrying out, decided again: its entry (or the detour paused in
		# front of it) runs on (LD9).
		return
	var carry := {}
	if (task.primitive == &"entry"
			and not _resume.is_empty()
			and (committed() or _guards(leaf, _entry.state.into))):
		# A detour's entry carries on: the new order replaces the one paused behind it (a fight that
		# began, the same order decided again), and the entry is not torn down at its stack or in
		# its threshold.
		carry = { "primitive": task.primitive, "params": task.params, "pending": _entry_pending }
	else:
		_drop_detour()
		_entry_pending = false
		_entry.abandon()  # A new choice ends any entry in progress (the stack is told).
	_adopt(leaf)
	if not carry.is_empty():
		_stash_order()
		task.primitive = carry["primitive"]
		task.params = carry["params"]
		_entry_pending = carry["pending"]


## Whether the entry guard applies to `leaf` for a doorway into room `into`: a walk (move / engage /
## interact, or a throw from a throw spot) that is not a retreat, while the NPC is not under fire,
## or, under fire, into the room the shots came from (`fight.into_the_shots`).
func _guards(leaf: Dictionary, into: String) -> bool:
	var params: Dictionary = leaf.get("params", {})
	var prim: StringName = leaf.get("primitive", &"hold")
	var walks: bool = (prim in [&"move", &"engage", &"interact", &"defend", &"ambush"]
			or (prim == &"throw" and bool(params.get("walk", false))))
	return (tuning.entry_guard.enabled
			and walks
			and bool(params.get("entry_guard", true))
			and (not _perception.under_fire() or fight.into_the_shots(into)))


## Take `leaf` as the running order.
func _adopt(leaf: Dictionary) -> void:
	task.held = false
	_join_done = false
	task.primitive = leaf.get("primitive", &"hold")
	task.params = leaf.get("params", {})
	task.path = leaf.get("path", [])
	task.labels = leaf.get("labels", [])
	task.leaf_ms = GameClock.msec()
	task.arrived = false
	errand.act_armed = false
	task.commit_timer = tuning.decision.max_commit_time
	task.arrive_room = str(task.params.get("arrive_room", ""))
	task.look_around = bool(task.params.get("look_around", false))
	# Room sample points are built on arrival, once we know which room we're in.
	errand.coverage.reset()
	_watch.reset()
	task.point = _loco.reachable(task.params["point"]) if task.params.has("point") else Vector2.ZERO
	errand.target_obj = null
	_combat.throw.end()
	grenades.throw_wait = -1.0
	fight.engage_id = 0
	var target_id: int = task.params.get("target_id", 0)
	if target_id != 0:
		fight.engage(target_id)
	match task.primitive:
		&"engage", &"melee":
			if fight.engage_id == 0:
				task.primitive = &"hold"  # The target was lost while deciding; re-decide.
				task.resolved = true
				return
			_combat.begin_fight()
			task.tactic_timer = tuning.decision.tactic_interval
			_perception.note_engaged()  # Commit to the fight (refreshed by firing).
		&"interact":
			errand.target_obj = task.params.get("object")
			errand.interact_id = task.params.get("id", "")
		&"reload":
			fight.reload_started = false
		&"entry":
			_entry_pending = true
		&"throw":
			grenades.begin_throw_order()
		&"defend", &"ambush":
			task.point = _loco.reachable(task.params.get("spot", _character.global_position))
		&"follow":
			orders.follow_to = Vector2.INF
	# (Refused: an order kept and held, no room for it.)
	orders.say_step("refused" if task.params.get("refused", false) else "moving")


## A steady stance for when no decision can be had (Von unreachable): stop and watch any known
## hostile.
func fallback() -> void:
	orders.awaiting = false
	_drop_detour()
	_entry.abandon()  # No decision to be had: an entry in progress is given up (the stack is told).
	task.primitive = &"hold"
	task.params = {}
	task.path = []
	task.labels = []
	errand.target_obj = null


# --- Per-tick bookkeeping ---------------------------------------------------------------------


## Resolve what the NPC currently knows from the perception's contact list (the engaged contact's
## last-known body/position/inside state) and advance the commitment timers. If the engaged contact
## is no longer known (its sighting decayed) or no longer hostile, a fight retargets to the nearest
## other known hostile; with none left, a leaf that needs a target ends and this returns true so the
## controller re-decides. All acting reads these rather than true positions, so the NPC only ever
## acts on what it has perceived.
func update_known(known: Array, delta: float) -> bool:
	task.commit_timer -= delta
	task.tactic_timer -= delta
	fight.known = known
	fight.hostiles = known.filter(func(c): return c["hostile"])
	if grenades.throw_target_gone():
		grenades.end_throw()
		return true
	if fight.engage_id == 0:
		return false
	var engaged: Dictionary = {}
	for c in fight.hostiles:
		if c["id"] == fight.engage_id:
			engaged = c
	if not engaged.is_empty() and not engaged["visible"]:
		# The one it is fighting has slipped out of sight and another stands in plain view: fight
		# that one.
		var seen: Array = fight.hostiles.filter(func(c): return c["visible"])
		if not seen.is_empty():
			engaged = seen[0]
			fight.engage_id = engaged["id"]
	if engaged.is_empty():
		engaged = fight.hostiles[0] if not fight.hostiles.is_empty() else {}
		fight.engage_id = engaged.get("id", 0)
	if not engaged.is_empty():
		fight.engage_node = engaged["node"]
		fight.engage_pos = engaged["pos"]
		fight.engage_inside = engaged.get("inside", false)
		return false
	if fight.needs_target():
		task.primitive = &"hold"
		return true
	return false


## Whether the running leaf wants a new decision now: a fight still moving into position holds until
## its safety cap; once in position it re-asks its tactic every `tuning.decision.tactic_interval` or
## when the engagement lapses; a move or approach holds until it completes (which forces a decision)
## or its safety cap runs out; a hold follows the decide cadence.
func wants_decision(decide_timer_elapsed: bool) -> bool:
	match task.primitive:
		&"engage", &"melee":
			return fight.wants_decision()
		&"move":
			# Hold through room coverage; it ends itself (all seen, or the budget runs out).
			var covering := task.look_around and task.arrived and not task.resolved
			return not covering and task.commit_timer <= 0.0
		&"interact", &"reload", &"throw":
			return task.commit_timer <= 0.0
		&"entry", &"follow":
			# An entry ends itself: the room clear, or the entry given up. A follower keeps with its
			# leader until something forces a decision.
			return false
		&"defend", &"ambush":
			return orders.post_wants_decision()
	return decide_timer_elapsed


# --- Running the primitive --------------------------------------------------------------------


## Carry out the running primitive this tick.
func apply(delta: float) -> void:
	if task.primitive != &"follow":
		gait.catching_up = false
	_combat.tick(delta)
	errand.set_up_walk(delta)
	if not grenades.evade.is_empty():
		grenades.apply_evade(delta)
		return
	match task.primitive:
		&"move":
			errand.apply_move(delta)
		&"engage":
			fight.apply_engage(delta)
		&"melee":
			fight.apply_melee()
		&"interact":
			errand.apply_interact()
		&"reload":
			fight.apply_reload()
		&"entry":
			_apply_entry(delta)
		&"throw":
			grenades.apply_throw(delta)
		&"defend", &"ambush":
			orders.apply_defend()
		&"follow":
			orders.apply_follow()
		_:
			errand.apply_hold()
	if orders.awaiting and not committed() and _walking():
		# The order is being decided on: stop the walk it replaces, as an arrived move stands.
		_character.movement.move_input = Vector2.ZERO
	if _loco.crowd.take_blocked():
		_way_blocked()
	_watch.apply(self, delta)
	_guard_clock += delta
	_entry_guard()
	_combat.continue_burst()
	_character.movement.run_input = gait.should_run()
	_combat.apply_back_off(delta)
	gait.apply_posture(delta)
	gait.running = _character.movement.is_running()
	gait.posture = _character.movement.posture()
	fight.reloading = _character.ammo.is_reloading()


## Whether the running primitive is on a walk an order replaces (LD6): a move that is not chosen
## under COMBAT (a search's walk and cover, an investigation's, an idle walk), an entry's approach
## to its slot, a defend or ambush walk to its post, a throw's walk to its throw spot, an
## interaction's walk to its object. Not a fight (an engage arrived or on its way, a melee, a
## reload, a hold, and a move chosen under COMBAT: an advance, a retreat, a locate, whose path
## starts at `combat`) nor the rest of an entry (the pie, the crossing, the corner, the clear, the
## cover, the rear: one stopped there stands in the doorway's funnel).
func _walking() -> bool:
	match task.primitive:
		&"move":
			return not in_combat()
		&"entry":
			return _entry.state.phase == "approach"
		&"defend", &"ambush", &"follow":
			return not task.arrived
		&"throw":
			return _combat.throw.stage == "walk"
		&"interact":
			return (not errand.in_interaction
					and errand.target_obj != null
					and is_instance_valid(errand.target_obj)
					and not errand.interaction_in_reach())
	return false


## Whether the walk the running primitive is on keeps out of the doorway views (E18): the walks the
## entry guard covers, so a move, an engage or an interact that is not a retreat, a throw's walk to
## its throw spot, and an entry's approach to its stack (its other walks, the pie and the crossing,
## are the entry's own), while the NPC is not under fire. Not an evade. An ordered stack's walk does
## whatever `entry_enabled` says (D4).
func _keeps_out_of_views() -> bool:
	if (not tuning.entry_guard.enabled
			or not (_perception.entry_enabled or orders.ordered_stack())
			or not grenades.evade.is_empty()
			or _perception.under_fire()):
		return false
	if task.primitive == &"entry":
		return _entry.state.phase == "approach"
	if task.primitive == &"throw":
		return _combat.throw.stage == "walk"
	return (task.primitive in [&"move", &"engage", &"interact", &"defend", &"ambush"]
			and bool(task.params.get("entry_guard", true)))


## A body seals the only way of the walk the primitive is on and stays (`Locomotion`'s
## `crowd.take_blocked`): re-plan, so the NPC is never held for ever. A move, an engage, a melee or
## an interact re-decides (another walk, or the same one held), and so does a throw still walking to
## its throw spot or closing on its spot (not once the wind-up has begun); an entry re-plans its own
## walk (`Entry.way_blocked`) and, when it gives the entry up, re-decides too, or, as a detour,
## hands the walk back to the order it paused. An evade (not a primitive: it replaces the order)
## holds the best spot it has until the burst.
func _way_blocked() -> void:
	if task.primitive in [&"move", &"engage", &"melee", &"interact", &"defend", &"ambush"]:
		task.resolved = true
		task.resolve_reason = "way blocked"
	elif task.primitive == &"throw" and _combat.throw.stage in ["walk", "aim"]:
		grenades.end_throw()
		task.resolve_reason = "way blocked"
	elif task.primitive == &"entry" and _entry.way_blocked():
		_finish_entry()
		if task.resolved:
			task.resolve_reason = "way blocked"
	elif task.primitive == &"follow":
		task.arrived = true  # It stands where it is held until its spot moves on.


## Entry: start the entry on the primitive's first tick, then run its phases (the watch stage shoots
## a threat in sight in every one of them). Done (the room clear, or the entry given up) →
## re-decide.
func _apply_entry(delta: float) -> void:
	_entry.state.gaze_held = not _watch.threat.is_empty()
	_entry.state.hostile_in_view = _hostile_in_view()
	if _entry_pending and _begin_pending_entry(delta):
		return
	if _entry.state.held_back:
		if _detour_first(delta):
			return
		# The way is clear: the entry begins again, from the claims heard meanwhile (others' held
		# back like its own), and its claim goes out.
		_entry.reset()
		if not _entry.begin(task.params):
			_finish_entry()
			return
	if _entry.step(delta):
		_finish_entry()
		return
	if orders.join_over():
		# Its leader's stack went in and cleared the room without it (LD25, D26): it follows again
		# now, not once its entry would have ended. One inside holds the room until its entry ends.
		_join_done = true
		task.resolved = true
		task.resolve_reason = "join over"
	if _entry.holding_for_go():
		orders.say_step("in_position")  # Ready in its slot and held for the leader's go (LD13).
	if task.held and not _entry.throwing():
		# The stun is away (or the bang given up): the decision held off for it is taken now, from
		# where it stands.
		task.held = false
		task.resolved = true
		task.resolve_reason = "after the bang"


## Begin the pending entry on its first tick, once the doorway's slots are laid (or `ROUTE_WAIT` s
## have gone by), and hold an ordered stack's claim back while its way is read. True when the tick
## ends here: still waiting for the slots, or the entry could not begin (and is finished).
func _begin_pending_entry(delta: float) -> bool:
	if not _entry.laid(task.params) and _route_wait < ROUTE_WAIT:
		# The doorway's slots are laid once the nav map is baked: a stack claims nothing before.
		_route_wait += delta
		_character.movement.move_input = Vector2.ZERO
		return true
	_entry_pending = false
	_route_wait = 0.0
	if not _entry.begin(task.params):
		if StackClaim.is_join(task.params):
			# No slot in its leader's stack (a dead end, E20): the join is refused and it follows
			# again (LD24, LD25).
			_perception.end_order(task.params.get("order_id"), "refused")
		_finish_entry()
		return true
	_entry.state.held_back = (_resume.is_empty()
			and Orders.ordered_entry(task.params)
			and _entry.state.phase == "approach")
	return false


## An ordered stack's way to its doorway (D4, LD9), read before the member's claim goes out: its
## entry has begun (its slot, its side and the approach's waypoints are worked out) and holds its
## claim back (`Entry.state.held_back`) while the whole walk to the slot, leg by leg as the approach
## walks it (`AgentPerception.walk_route`: out of the room being entered and its doorway's view), is
## read for a threshold into a room not cleared (`threshold_ahead`; the room being entered and the
## doorway it stacks at left out), and, with no other recipient coming to the doorway, a doorway
## view it would cross (E15, `passing_ahead`; not one of the room being entered, which the stack
## clears). The first is gone through by entry first, as a detour (`_begin_detour`): the entry is
## dropped unheard, so no claim was made and none is given up; the order's entry starts afresh once
## the detour is over, and reads the way again. True while it is detouring or waits (at most
## `ROUTE_WAIT` s) for a map round the views to be baked; false when the way is clear and the claim
## is due.
func _detour_first(delta: float) -> bool:
	if not tuning.entry_guard.enabled or _perception.under_fire():
		return false
	var opening: String = _entry.state.opening
	var into: String = _entry.state.into
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
		_character.movement.move_input = Vector2.ZERO
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
	if (gate["opening"] == _entry.state.opening
			or str(gate["into"]) == _entry.state.into
			or float(_guard_off.get(gate["opening"], -1.0)) > _guard_clock):
		return {}
	return gate


## Whether the order the pending entry stacks under names another living member: a team is coming to
## the doorway, so nobody leaves the way to it to cover a doorway on the way (E15, as for a stack
## others claim).
func _entry_recipients_coming() -> bool:
	var held: Dictionary = _perception.order()
	if str(held.get("id", "")) != str(task.params.get("order_id", "")):
		return false
	return (held.get("to", []) as Array).any(
		func(m): return is_instance_valid(m) and m != _character and m.get("is_dead") != true,
	)


## Whether a hostile stands in view for the entry's purposes (E14): the threat holding the NPC's
## eyes is seen now, or was a moment ago (`tuning.watch.lost_gaze` s), and there is a line of fire
## to it from here, so it can be engaged from outside. A hostile remembered from longer ago, or one
## seen but behind a wall or out of range (nothing to engage it with from outside), does not hold an
## entry outside.
func _hostile_in_view() -> bool:
	return (not _watch.threat.is_empty()
			and (bool(_watch.threat["visible"])
					or float(_watch.threat["age"]) <= tuning.watch.lost_gaze)
			and _combat.has_line_of_fire(_watch.threat))


## The entry is over, or could not start. As the NPC's own order (ENTER) it resolves and the NPC
## re-decides. As a detour (`_begin_detour`) it hands the walk back to the order it paused, which
## carries on from where the entry left the NPC; a doorway whose room is still not cleared (the
## entry did not get to the end) is left alone for `tuning.entry_guard.rearm` s.
func _finish_entry() -> void:
	task.held = false
	if _resume.is_empty():
		task.primitive = &"hold"
		task.resolved = true
		return
	if _entry.state.secured:
		# Secured in passing: not again for a while.
		_guard_off[_entry.state.opening] = _guard_clock + tuning.entry_guard.secure_time
	elif not _perception.is_cleared(_entry.state.into):
		_guard_off[_entry.state.opening] = _guard_clock + tuning.entry_guard.rearm
	_resume_order()


## Hand the walk back to the order a detour paused.
func _resume_order() -> void:
	var r := _resume
	_resume = {}
	task.primitive = r["primitive"]
	task.params = r["params"]
	task.path = r["path"]
	task.labels = r["labels"]
	task.point = r["point"]
	task.arrived = r["arrived"]
	task.look_around = r["look_around"]
	task.arrive_room = r["arrive_room"]
	errand.act_armed = r["act_armed"]
	_entry_pending = bool(r.get("entry_pending", false))
	# The order's cap runs from here: the entry took the time it took.
	task.commit_timer = tuning.decision.max_commit_time
	if task.primitive == &"throw":
		# The walk to the throw spot goes on from where the entry left it.
		grenades.begin_throw_order()


## The entry guard (E9): a walk that is about to cross into a room that is not cleared goes in by
## tactical entry, whatever order it came from (a search or explore, a lead, a closing-in, the way
## to an object or to a throw spot, the front entrance). It reads the walk the nav agent was just
## given rather than the leaf's destination, so a path through an intermediate room, a reposition in
## a fight and the way to a doorway itself are all covered. Exempt: a retreat
## (`tuning.entry_guard.enabled: false` on its node), an NPC under fire (but for a walk into the
## room the shots came from, `fight.into_the_shots`), an entry already running, and anything that is
## not walking.
func _entry_guard() -> void:
	if task.primitive == &"entry":
		_guard_running_entry()
		return
	if not _walk_guarded():
		return
	var walk: Dictionary = _loco.path_ahead()
	if walk.is_empty():
		return
	var gate: Dictionary = _perception.threshold_ahead(
		walk["path"], walk["index"], tuning.entry_guard.reach,
	)
	if not _perception.under_fire():
		var passing := _passing_gate(walk, gate)
		if not passing.is_empty():
			gate = passing
	elif gate.is_empty() or not fight.into_the_shots(str(gate["into"])):
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
			and not fight.into_the_shots(_entry.state.into)):
		# Shot at before it crossed: no time to stack. (Once crossing it finishes the crossing; into
		# the shots it stacks.)
		_cancel_detour()
	elif _resume.is_empty() and not _entry_pending and _entry.state.phase == "approach":
		_guard_approach()


## Whether the running primitive (not an entry) is on a walk the entry guard covers this tick: the
## guard on, the NPC stepping, a move, defend or ambush not yet arrived, an engage, an interaction
## or a throw's walk to its throw spot, and not a retreat (`tuning.entry_guard.enabled: false`).
func _walk_guarded() -> bool:
	if not tuning.entry_guard.enabled or _perception == null or not _perception.entry_enabled:
		return false
	match task.primitive:
		&"move", &"defend", &"ambush":
			if task.arrived:
				return false  # Holding at the destination, or covering the room by sight.
		&"engage", &"interact":
			pass
		&"throw":
			if _combat.throw.stage != "walk":
				return false  # Throwing where it stands: no walk to guard.
		_:
			return false
	return not ((_character.movement.move_input as Vector2).length() < 0.1
			or not bool(task.params.get("entry_guard", true)))


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
	var ordered := Orders.ordered_entry(task.params)
	if (not tuning.entry_guard.enabled
			or not (_perception.entry_enabled or ordered)
			or (_character.movement.move_input as Vector2).length() < 0.1
			or _perception.under_fire()):
		return
	var walk: Dictionary = _loco.path_ahead()
	if walk.is_empty():
		return
	var gate := {}
	if ordered:
		gate = _other_threshold(walk["path"], walk["index"], tuning.entry_guard.reach)
	var team_coming: bool = (_perception.entry_stack(_entry.state.opening).claimed()
			or (ordered and _entry_recipients_coming()))
	var passing := {} if team_coming else _passing_gate(walk, gate)
	if (not passing.is_empty()
			and passing["opening"] != _entry.state.opening
			and str(passing["into"]) != _entry.state.into):
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
		walk["path"], walk["index"], tuning.entry_guard.reach,
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
	task.primitive = &"entry"
	task.params = {
		"opening": gate["opening"],
		"into": gate["into"],
		"secure": bool(gate.get("secure", false)),
	}
	_entry_pending = true


## Give a detour's entry up (the stack is told) and carry on with the paused order, which walks
## straight through.
func _cancel_detour() -> void:
	var opening := str(task.params.get("opening", _entry.state.opening))
	_guard_off[opening] = _guard_clock + tuning.entry_guard.rearm
	_entry_pending = false
	_entry.abandon()
	_resume_order()


## Keep the running order whole in `_resume`, to come back when the entry ends.
func _stash_order() -> void:
	_resume = {
		"primitive": task.primitive, "params": task.params,
		"path": task.path, "labels": task.labels,
		"point": task.point, "arrived": task.arrived, "look_around": task.look_around,
		"arrive_room": task.arrive_room, "act_armed": errand.act_armed,
		# An ENTER order that is paused starts afresh when it comes back.
		"entry_pending": task.primitive == &"entry",
	}


## A new decision (or no decision to be had) ends a detour: the paused order is gone, and the
## doorway it was stacking at is left alone for `tuning.entry_guard.rearm` s so a fight that cut the
## entry short does not restart it every decision.
func _drop_detour() -> void:
	if _resume.is_empty():
		return
	var opening := str(task.params.get("opening", _entry.state.opening))
	_guard_off[opening] = _guard_clock + tuning.entry_guard.rearm
	_resume = {}


# --- The evade reflex (G16) -------------------------------------------------------------------


# --- Helpers ---------------------------------------------------------------------------------
