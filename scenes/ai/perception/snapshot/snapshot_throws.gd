extends RefCounted
## AI PERCEPTION sub-domain — SNAPSHOT THROWS. Writes the grenade option groups Von picks from
## (`docs/grenades.md` G17): a grenade thrown at a hostile hidden from the NPC's line of fire, or
## holding a room the NPC is outside of (`grenade_group`, per target), and one thrown where the
## shots at the NPC came from (`shots_grenade_group`), each from where it stands or from a throw
## spot a short walk away. A pure read of the event memory, the tactics geometry, the grenade
## geometry, the doorway views, the shared vocabulary and the knowledge handed in for the decision
## (`know`, set by `AgentSnapshot.build()`). `agent_snapshot.gd` holds it (`_throws`) beside the
## other option groups (`snapshot_options.gd`) and calls it from `build()`.

const SnapshotVocab = preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const AgentThrow = preload("res://scenes/ai/perception/agent_throw.gd")
const AgentSuspicion = preload("res://scenes/ai/perception/agent_suspicion.gd")
## Where along the stretch of the line back from a shot that lies in the room the shots came from a
## grenade is aimed, in order of preference (shares of the stretch, from where the line comes into
## the room): its middle first, then either side of it.
const SHOT_AIM_SHARES := [0.5, 0.35, 0.65, 0.2, 0.8]

## The knowledge the perception hands in for this decision (see `AgentSnapshot.build()`).
var know := {}
## Throw spots worked out for this decision, by burst spot, reach and room kept out of
## (`_throw_option`; cleared by `begin`).
var _throw_spots := {}
## The shared vocabulary and tuning; see snapshot_vocab.gd.
var _v: SnapshotVocab
## The agent's event memory (read-only here); see agent_memory.gd.
var _memory: RefCounted
## The combat geometry; see agent_tactics.gd.
var _tactics: RefCounted
## The doorway views and the walk round them; see agent_door_views.gd.
var _views: RefCounted
## The grenade geometry (the lob, the danger zone, the escape); see agent_throw.gd.
var _throw: AgentThrow


## Capture the shared vocabulary and the collaborators the groups read (`sources`). Called once by
## `AgentSnapshot.setup()`.
func setup(vocab: SnapshotVocab, sources: SnapshotSources) -> void:
	_v = vocab
	_memory = sources.memory
	_tactics = sources.tactics
	_views = sources.views
	_throw = sources.throw


## Start a decision's option groups: forget what the last one worked out (`know` is set by the
## caller).
func begin() -> void:
	_throw_spots.clear()


## Throwing a grenade at hostile `t`, one option per kind carried (a frag first), offered against a
## hostile that is hidden from the NPC's line of fire (a bullet would be stopped: low furniture, a
## corner), or whose last-known spot is in a room the NPC is outside of (a defender barricaded in a
## room: even with a line of fire it is grenaded, not only shot at, docs/grenades.md G17), at a spot
## within throw range with a clear lob over what lies between: from where the NPC stands, else from
## a throw spot a short walk away (`_throw_option`). Each option carries the tags the tactic's
## `drop_tags` drop it by: `ally_in_blast` (a known ally, seen or on the radio, would be inside the
## grenade's danger zone at that spot) and `no_safe_spot` (the NPC itself would be, from where it
## throws, and has no way to get safe before the fuse is out: nowhere to crouch behind cover that
## shields it, no spot out of the burst's line within reach in time). Empty with no grenade, a clear
## shot at a hostile in the NPC's own room (or outside with it), no lob from anywhere near or no
## known spot.
func grenade_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var kinds: Array = know.get("carried_grenades", [])
	var spot: Vector2 = t["pos"]
	var held := _held_room(ctx, spot)
	var hidden: bool = not a["line"]["clear"]
	if kinds.is_empty() or (not hidden and held.is_empty()):
		return { "summary": "", "options": [] }
	var cover: String = a["line"]["blocker"]
	var room := "" if held.is_empty() else _v.room_name(held["type"])
	var options: Array = []
	for kind: StringName in kinds:
		var what := "frag" if kind == &"frag" else "stun"
		var option := _throw_option(
			ctx,
			kind,
			spot,
			Rect2() if held.is_empty() else held["rect"],
			true,
		)
		if option.is_empty():
			continue
		if t["id"] != 0:
			option["params"]["target_id"] = t["id"]
		option["id"] = what
		option["label"] = (("%s %s behind their cover" % [what, t["name"]])
				if hidden
				else ("%s %s in the %s" % [what, t["name"], room]))
		option["desc"] = ((("%s grenade onto where %s is hidden, behind the %s"
				% [what, t["name"], cover])
				if hidden
				else ("%s grenade into the %s, onto where %s holds it" % [what, room, t["name"]]))
				+ _throw_from_text(ctx, option))
		options.append(option)
	if options.is_empty():
		return { "summary": "", "options": [] }
	var reach := _throw_reach_text(options)
	if hidden:
		return {
			"summary": "%s is hidden behind the %s, %s" % [t["name"], cover, reach],
			"options": options, "situation": "Your line to %s is blocked" % t["name"],
		}
	return {
		"summary": "%s holds the %s, a room you are outside of, %s" % [t["name"], room, reach],
		"options": options, "situation": "%s holds a room you are outside of" % t["name"],
		"held_room": room,
	}


## Throwing a grenade where the shots at the NPC came from (docs/grenades.md G17): shot at by
## someone it cannot see from a room it is outside of (the line back from a shot, `shot_from`, runs
## into that room), one option per kind carried, onto the stretch of that line inside the room
## (`_shots_aim`: from where it stands, else from a throw spot). The same tags as `grenade_group`.
## Only while under fire with no hostile known (the unbound COMBAT level, where LOCATE is not
## offered toward such a room: `shooter_group`); empty otherwise.
func shots_grenade_group(ctx: Dictionary, hostiles: Array) -> Dictionary:
	var kinds: Array = know.get("carried_grenades", [])
	if kinds.is_empty() or not hostiles.is_empty() or not _memory.under_fire():
		return { "summary": "", "options": [] }
	var options: Array = []
	var room := ""
	for kind: StringName in kinds:
		var aim := _shots_aim(ctx, kind)
		if aim.is_empty():
			continue
		var option: Dictionary = aim["option"]
		var what := "frag" if kind == &"frag" else "stun"
		room = _v.room_name(aim["room"]["type"])
		option["id"] = what
		option["label"] = "%s where the shots came from" % what
		option["desc"] = ("%s grenade into the %s, where the shots came from%s"
				% [what, room, _throw_from_text(ctx, option)])
		options.append(option)
	if options.is_empty():
		return { "summary": "", "options": [] }
	return {
		"summary": "the shots came from the %s, a room you are outside of, %s"
			% [room, _throw_reach_text(options)],
		"options": options, "situation": "The shots came from a room you are outside of",
		"held_room": room,
	}


## The room hostile-held spot `spot` lies in when the NPC is outside that room (outdoors, or in
## another room), or {}.
func _held_room(ctx: Dictionary, spot: Vector2) -> Dictionary:
	var theirs := HouseRooms.at(spot, _v.rooms)
	if theirs.is_empty():
		return {}
	var here := HouseRooms.at(ctx["self_pos"], _v.rooms)
	return {} if not here.is_empty() and here["key"] == theirs["key"] else theirs


## Where to throw a grenade of `kind` at the shots: `{ option, room }`, the throw (`_throw_option`)
## onto a line back from a shot at the NPC (`AgentSuspicion.shot_line`: from where it leaves the
## room the shot landed in to the wall behind) inside the first room along it the NPC is outside of,
## at the point nearest the middle of that stretch (`SHOT_AIM_SHARES`) it can lob onto from where it
## stands, else from a throw spot; {} when there is none.
func _shots_aim(ctx: Dictionary, kind: StringName) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var here := HouseRooms.at(self_pos, _v.rooms)
	for shot: Dictionary in _memory.recall_all(&"shot_from"):
		var best := _shot_stretch(AgentSuspicion.shot_line(_v.rooms, shot), shot["at"], here)
		if best.is_empty():
			continue
		for walk: bool in [false, true]:
			for share: float in SHOT_AIM_SHARES:
				var spot: Vector2 = (best["from"] as Vector2).lerp(best["to"], share)
				var option := _throw_option(ctx, kind, spot, best["room"]["rect"], walk)
				if not option.is_empty():
					return { "option": option, "room": best["room"] }
	return {}


## The stretch of the line back from a shot (`line`, the shot landing at `at`) inside the room it
## comes into first, nearest `at`, among the rooms but the one the NPC is in (`here`):
## `{ room, from, to }`, from where it comes into the room to where it leaves; {} when it runs into
## none.
func _shot_stretch(line: PackedVector2Array, at: Vector2, here: Dictionary) -> Dictionary:
	var best := {}
	var nearest := INF
	for room in _v.rooms:
		if not here.is_empty() and room["key"] == here["key"]:
			continue
		var r: Rect2 = room["rect"]
		var poly := PackedVector2Array([
			r.position,
			Vector2(r.end.x, r.position.y),
			r.end,
			Vector2(r.position.x, r.end.y),
		])
		for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, poly):
			var d := at.distance_to(piece[0])
			if d < nearest:
				nearest = d
				best = { "room": room, "from": piece[0], "to": piece[piece.size() - 1] }
	return best


## One grenade throw of `kind` onto `spot`, with its params and the tags the GRENADE tactic drops it
## by, or {} when there is no lob onto it in range from where the NPC stands nor (with `walk`) from
## a throw spot a short walk away (agent_tactics.gd `throw_spot`; never inside `keep_out`, the room
## the NPC is outside of that it throws into). `params.from` is where it throws from (where it
## stands, or the throw spot, with `params.walk`): the danger zone and the way out of it are judged
## from there. The caller words it (`id`, `label`, `desc`) and adds the hostile it is thrown at
## (`params.target_id`).
func _throw_option(
	ctx: Dictionary,
	kind: StringName,
	spot: Vector2,
	keep_out: Rect2,
	walk: bool,
) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var space = ctx["space"]
	var rids: Array = know["character_rids"]
	var from := self_pos
	var route := 0.0
	if not _throw.can_lob(space, self_pos, spot, _throw.range_of(kind), rids):
		if not walk:
			return {}
		var way := _throw_way(ctx, kind, spot, keep_out)
		if way.is_empty():
			return {}
		from = way["point"]
		route = way["route_len"]
	var radius := _throw.radius_of(kind)
	var ally := _ally_in_blast(ctx, kind, radius, spot)
	var cornered := _cornered(ctx, kind, radius, spot, from)
	var params := {
		"point": spot,
		"kind": kind,
		"radius": radius,
		"slot": AgentThrow.SLOTS[kind],
		"from": from,
		"walk": from != self_pos,
	}
	return { "params": params, "route_len": route,
		"tags": { "inside": _v.is_inside(spot), "ally_in_blast": ally, "no_safe_spot": cornered } }


## The throw spot to throw a grenade of `kind` onto `spot` from, never inside `keep_out`
## (`AgentTactics.throw_spot`: `{ point, route_len, ... }`, {} for none), worked out once per
## decision: a frag and a stun of the same reach share their throw spot.
func _throw_way(ctx: Dictionary, kind: StringName, spot: Vector2, keep_out: Rect2) -> Dictionary:
	var space = ctx["space"]
	var rids: Array = know["character_rids"]
	var reach := _throw.reach_of(kind)
	# A frag and a stun of the same reach share their throw spot.
	var key := [spot, reach, keep_out]
	if not _throw_spots.has(key):
		var aim := ThrowAim.new()
		aim.spot = spot
		aim.reach = reach
		aim.keep_out = keep_out
		aim.lob = func(p: Vector2) -> bool:
			return _throw.throw_clear_on_arrival(space, p, spot, rids)
		aim.route = func(p: Vector2) -> Dictionary: return _throw_walk(ctx, p)
		_throw_spots[key] = _tactics.throw_spot(ctx, aim, rids)
	return _throw_spots[key]


## Whether the NPC, throwing a grenade of `kind` and `radius` onto `spot` from `from`, would be in
## its danger zone there with no way to get safe before the fuse is out (`AgentThrow.escape` finds
## no spot or cover in time).
func _cornered(
	ctx: Dictionary,
	kind: StringName,
	radius: float,
	spot: Vector2,
	from: Vector2,
) -> bool:
	var space = ctx["space"]
	var rids: Array = know["character_rids"]
	var threat := GrenadeThreat.new()
	threat.kind = kind
	threat.radius = radius
	threat.burst = spot
	if not _throw.in_zone(space, threat, from, _throw.stand_height(), rids):
		return false
	threat.fuse_left = _throw.fuse_of(kind)
	var runner := GrenadeRunner.new()
	runner.from = from
	runner.speed = _throw.run_speed()
	var out: Dictionary = _throw.escape(space, ctx["map"], threat, runner, rids)
	return (out["spot"] as Vector2) == Vector2.INF


## The walk to throw spot `p` as the NPC would walk it (agent_door_views.gd `walk_route`: round the
## doorway views when it would take that, E18), and whether the entry guard would stop it on the way
## (`detour`): a doorway into a room not cleared that it crosses (E9), or a doorway view it comes
## into with no way round it (E15). `{ path, len, detour }`. The guard runs only where doorway views
## are kept out of (`AgentDoorViews.avoid_views`: tactical entry and the guard on).
func _throw_walk(ctx: Dictionary, p: Vector2) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var way: Dictionary = _views.walk_route(self_pos, p, ctx["map"], ctx["space"])
	var detour := false
	if _views.avoid_views:
		var cleared := func(key: String) -> bool:
			return _memory.age_of(&"cleared_room", "key", key) <= _v.tuning.memory.search_ttl
		detour = not _views.threshold_ahead(way["path"], 0, self_pos, cleared, INF).is_empty() \
			or (not way["doors"] and not (way["views"] as Array).is_empty())
	return { "path": way["path"], "len": way["len"], "detour": detour }


## What a throw from a throw spot adds to its option's desc: where the spot is and the walk there ("
## — from the kitchen to the east, short route"); "" for a throw from where the NPC stands.
func _throw_from_text(ctx: Dictionary, option: Dictionary) -> String:
	var params: Dictionary = option["params"]
	if not params["walk"]:
		return ""
	var from: Vector2 = params["from"]
	return " — from %s to the %s, %s route" % [
		_v.place(from).trim_prefix("in "), _v.compass(from - (ctx["self_pos"] as Vector2)),
		_v.route_band(option["route_len"]),
	]


## How a grenade group's summary says the throw is in reach: "within throwing range" when one of
## `options` is thrown from where the NPC stands, "within throwing range from a spot nearby" when
## each needs a walk to a throw spot.
func _throw_reach_text(options: Array) -> String:
	if options.any(func(o): return not o["params"]["walk"]):
		return "within throwing range"
	return "within throwing range from a spot nearby"


## Whether a known ally (seen, or one that radioed where it was) is inside the danger zone of a
## grenade of `kind` and `radius` that would burst at `spot`.
func _ally_in_blast(ctx: Dictionary, kind: StringName, radius: float, spot: Vector2) -> bool:
	var found := {}
	for al in ctx["allies"]:
		found[al["id"]] = al["pos"]
	for c in ctx["callouts"]:
		if not found.has(c["id"]):
			found[c["id"]] = c.get("position", Vector2.INF)
	var threat := GrenadeThreat.new()
	threat.kind = kind
	threat.radius = radius
	threat.burst = spot
	for pos: Vector2 in found.values():
		if _throw.in_zone(ctx["space"], threat, pos, _throw.stand_height(), know["character_rids"]):
			return true
	return false
