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
## `Combat` module (shots, punches, bursts, the peek-and-cover cycle) and, through its errand part,
## a `SearchCoverage` module; it reads the world only through the PERCEPTION sub-domain (known
## contacts, combat geometry, engagement memory) and drives the character only through its public
## controller contract (`movement.move_input` / `movement.aim_point`, `inventory.select_slot`,
## `weapon.shoot`, `weapon.melee`, `use.interact_with`, `use.end_interaction`). Every tunable is
## read live from the NPC's tuning (`NpcTuning`, handed in by `setup`), by the behaviour and by each
## of its modules; `apply_config(npc_squad)` hands in the side's squad.

const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")
const Combat := preload("res://scenes/ai/behavior/combat.gd")
const SearchCoverage := preload("res://scenes/ai/behavior/search_coverage.gd")
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const RunningLeaf := preload("res://scenes/ai/behavior/running_leaf.gd")
const Watch := preload("res://scenes/ai/behavior/watch.gd")
## The parts (`fight`, `errand`, `gait`, `grenades`, `orders`, `entries`).
const Fight := preload("res://scenes/ai/behavior/behavior_fight.gd")
const Errand := preload("res://scenes/ai/behavior/behavior_errand.gd")
const Gait := preload("res://scenes/ai/behavior/behavior_gait.gd")
const Grenades := preload("res://scenes/ai/behavior/behavior_grenades.gd")
const Orders := preload("res://scenes/ai/behavior/behavior_orders.gd")
const Entries := preload("res://scenes/ai/behavior/behavior_entries.gd")
## How each phase of a tactical entry reads in the status line.
const ENTRY_PROGRESS := {
	"approach": "heading for the door", "stack": "stacked at the door", "pie": "slicing the pie",
	"bang": "throwing a stun in", "cross": "going in", "corner": "taking a corner",
	"clear": "clearing the room", "cover": "covering the doors on", "rear": "holding the door",
}

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
## The entries: the entry primitive over `Entry`, the entry guard and its detours, and the entry
## read-outs; see behavior_entries.gd.
var entries: Entries
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
	entries = Entries.new(self)
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


## Hand in its side's `squad`, to its orders part and its entry module; they and the other modules
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
			return entries.pending or _entry.state.phase not in ["", "done"]
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
		"entry": _json_safe(entries.debug()),
		"loco": _loco.debug_state(),
		"order": orders.order_leaf(),
	}


## Whether the NPC is committed: crossing a doorway, or with its arm drawn back to throw (a grenade
## cannot be called back). The controller holds every re-decision until it is through.
func committed() -> bool:
	return ((task.primitive == &"entry" and _entry.committed())
			or (task.primitive == &"throw" and _combat.throw.stage == "windup"))


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
	if committed() and entries.resume.is_empty():
		# Crossing a doorway on its own ENTER, throwing the bang, or winding up a throw: a decision
		# that was in flight waits (it ends in a re-decision). The bang's thrower (E17) throws
		# first, then decides again from where it stands (`entries.apply`).
		task.held = task.held or (task.primitive == &"entry" and _entry.throwing())
		return
	if orders.same(leaf):
		# The ordered stack it is carrying out, decided again: its entry (or the detour paused in
		# front of it) runs on (LD9).
		return
	var carry := {}
	if (task.primitive == &"entry"
			and not entries.resume.is_empty()
			and (committed() or entries.guards(leaf, _entry.state.into))):
		# A detour's entry carries on: the new order replaces the one paused behind it (a fight that
		# began, the same order decided again), and the entry is not torn down at its stack or in
		# its threshold.
		carry = { "primitive": task.primitive, "params": task.params, "pending": entries.pending }
	else:
		entries.drop_detour()
		entries.pending = false
		_entry.abandon()  # A new choice ends any entry in progress (the stack is told).
	_adopt(leaf)
	if not carry.is_empty():
		entries.stash_order()
		task.primitive = carry["primitive"]
		task.params = carry["params"]
		entries.pending = carry["pending"]


## Take `leaf` as the running order.
func _adopt(leaf: Dictionary) -> void:
	task.held = false
	entries.join_done = false
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
			entries.pending = true
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
	entries.drop_detour()
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
			entries.apply(delta)
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
	entries.guard_clock += delta
	entries.guard()
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
		entries.finish()
		if task.resolved:
			task.resolve_reason = "way blocked"
	elif task.primitive == &"follow":
		task.arrived = true  # It stands where it is held until its spot moves on.
