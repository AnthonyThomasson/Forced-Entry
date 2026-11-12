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
const ThrowScan := preload("res://scenes/ai/perception/throw_scan.gd")
const ThrowSearch := preload("res://scenes/ai/perception/snapshot/throw_search.gd")
## Where along the stretch of the line back from a shot that lies in the room the shots came from a
## grenade is aimed, in order of preference (shares of the stretch, from where the line comes into
## the room): its middle first, then either side of it.
const SHOT_AIM_SHARES := [0.5, 0.35, 0.65, 0.2, 0.8]

## The knowledge the perception hands in for this decision (see `AgentSnapshot.build()`).
var know := {}
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


## Whether `grenade_group` would offer a throw at hostile `t` (analysis `a`): the same as
## `not grenade_group(ctx, t, a)["options"].is_empty()`, without its tags, wording or the ally and
## escape checks, and with the throw-spot search stopped at the first walk that reaches one.
func grenade_possible(ctx: Dictionary, t: Dictionary, a: Dictionary) -> bool:
	return _run_search(ctx, [{ "of": "target", "t": t, "a": a }])


## Whether `shots_grenade_group` would offer a throw where the shots came from: the same as
## `not shots_grenade_group(ctx, hostiles)["options"].is_empty()`, by the cheap search of
## `grenade_possible`.
func shots_possible(ctx: Dictionary, hostiles: Array) -> bool:
	return _run_search(ctx, [{ "of": "shots", "hostiles": hostiles }])


## The existence search over `plan` (`begin_search`), run to its end.
func _run_search(ctx: Dictionary, plan: Array) -> bool:
	var search := begin_search(ctx, plan, ThrowScan.WHOLE)
	while not search.done():
		search.step()
	return search.found


## The room hostile-held spot `spot` lies in when the NPC is outside that room (outdoors, or in
## another room), or {}.
func _held_room(ctx: Dictionary, spot: Vector2) -> Dictionary:
	var theirs := HouseRooms.at(spot, _v.rooms)
	if theirs.is_empty():
		return {}
	var here := HouseRooms.at(ctx["self_pos"], _v.rooms)
	return {} if not here.is_empty() and here["key"] == theirs["key"] else theirs


## Where to throw a grenade of `kind` at the shots: `{ option, room }`, the throw (`_throw_option`)
## onto the first of the aims (`_shots_aims`) it can lob onto, from where it stands, else from a
## throw spot; {} when there is none.
func _shots_aim(ctx: Dictionary, kind: StringName) -> Dictionary:
	for aim: Dictionary in _shots_aims(ctx):
		var option := _throw_option(ctx, kind, aim["spot"], aim["room"]["rect"], aim["walk"])
		if not option.is_empty():
			return { "option": option, "room": aim["room"] }
	return {}


## The places a grenade may be aimed at the shots, in order of preference, each `{ spot, room,
## walk }`: for each shot recalled (`AgentSuspicion.shot_line`: from where the line leaves the room
## the shot landed in to the wall behind) its stretch inside the first room along it the NPC is
## outside of, the points nearest the middle of it first (`SHOT_AIM_SHARES`), thrown from where the
## NPC stands (`walk` false) before from a throw spot (`walk` true).
func _shots_aims(ctx: Dictionary) -> Array:
	var here := HouseRooms.at(ctx["self_pos"], _v.rooms)
	var aims: Array = []
	for shot: Dictionary in _memory.recall_all(&"shot_from"):
		var best := _shot_stretch(AgentSuspicion.shot_line(_v.rooms, shot), shot["at"], here)
		if best.is_empty():
			continue
		for walk: bool in [false, true]:
			for share: float in SHOT_AIM_SHARES:
				aims.append({
					"spot": (best["from"] as Vector2).lerp(best["to"], share),
					"room": best["room"],
					"walk": walk,
				})
	return aims


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
	var key := _throw_key(ctx, kind, spot, keep_out)
	var memo := memo_of(ctx)
	var spots: Dictionary = memo["spots"]
	if not spots.has(key):
		var aim := _throw_aim(ctx, kind, spot, keep_out)
		spots[key] = _tactics.throw_spot(
			ctx, aim, know["character_rids"], _candidates(ctx, aim, key)
		)
	return spots[key]


## What this decision has worked out for its throws, held by its context so that the decision that
## made it is the only one to read it: `spots` (the throw spot by key, `_throw_way`), `points` (the
## candidate points for a key: what the existence search and the full one share) and `exists`
## (whether a throw spot exists, for the throws asked only whether one is possible). A context made
## by hand holds none yet.
func memo_of(ctx: Dictionary) -> Dictionary:
	if not ctx.has("throw_memo"):
		ctx["throw_memo"] = { "spots": {}, "points": {}, "exists": {} }
	return ctx["throw_memo"]


## Begin a search of the sources in `plan`, in order, for a throw the NPC could make: each
## `{ of: "known", value }` (a group already built answers), `{ of: "shots", hostiles }` (the shots'
## throws), `{ of: "target", t, a }` (a hostile's throws). A search is what `grenade_possible` and
## `shots_possible` run, in steps of `block` raw candidates (`ThrowSearch`).
func begin_search(ctx: Dictionary, plan: Array, block: int) -> ThrowSearch:
	var search := ThrowSearch.new()
	search.begin(self, ctx, plan, block)
	return search


## What a search's next step is, working through what needs no price first: a throw clear from where
## the NPC stands, a spot already worked out, the next source's throws. Stops at the next block of
## candidates, rank pass or route (`ThrowScan.Kind`), or the end (`DONE`, `found` the answer).
func search_ready(search: ThrowSearch) -> int:
	while not search.over and search.scan == null:
		if search.at < search.queries.size():
			_query(search, search.queries[search.at])
		elif search.source < search.plan.size():
			_expand(search, search.plan[search.source])
			search.source += 1
		else:
			search.over = true
	if search.over:
		return ThrowScan.Kind.DONE
	return search.scan.kind


## Run a search's next step: a block, the rank pass or a route of the spot search in hand. A spot
## search that ends is kept (the candidates, and whether a spot exists) for the decision's later
## asks, and its answer is the query's.
func search_step(search: ThrowSearch) -> void:
	if search_ready(search) == ThrowScan.Kind.DONE:
		return
	var scan: ThrowScan = search.scan
	scan.step(search.block)
	var memo := memo_of(search.ctx)
	if scan.candidates_done:
		(memo["points"] as Dictionary)[search.key] = scan.points
	if scan.done():
		(memo["exists"] as Dictionary)[search.key] = scan.found
		search.scan = null
		search.found = scan.found
		search.over = scan.found
		search.at += 1


## The queries of source `source` of a search, to try in order.
func _expand(search: ThrowSearch, source: Dictionary) -> void:
	search.at = 0
	search.queries = []
	match source["of"]:
		"known":
			search.found = source["value"]
			search.over = search.found
		"shots":
			search.queries = _shots_queries(search.ctx, source["hostiles"])
		"target":
			search.queries = _target_queries(search.ctx, source["t"], source["a"])


## The throws asked at the shots' origin (`shots_grenade_group`): per kind carried, the aims in
## order, none unless under fire with no hostile known.
func _shots_queries(ctx: Dictionary, hostiles: Array) -> Array:
	var kinds: Array = know.get("carried_grenades", [])
	if kinds.is_empty() or not hostiles.is_empty() or not _memory.under_fire():
		return []
	var aims := _shots_aims(ctx)
	var out: Array = []
	for kind: StringName in kinds:
		for aim: Dictionary in aims:
			out.append({
				"kind": kind, "spot": aim["spot"], "keep_out": aim["room"]["rect"],
				"walk": aim["walk"],
			})
	return out


## The throws asked at hostile `t` (`grenade_group`): one per kind carried, from a throw spot when
## not from where the NPC stands, none against a clear shot in the NPC's own room.
func _target_queries(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Array:
	var kinds: Array = know.get("carried_grenades", [])
	var spot: Vector2 = t["pos"]
	var held := _held_room(ctx, spot)
	if kinds.is_empty() or (a["line"]["clear"] and held.is_empty()):
		return []
	var keep_out := Rect2() if held.is_empty() else held["rect"] as Rect2
	return kinds.map(func(kind: StringName) -> Dictionary:
		return { "kind": kind, "spot": spot, "keep_out": keep_out, "walk": true })


## One query of a search (`_throw_option`'s possibility, `search_ready`): found when a lob is clear
## from where the NPC stands, or (walking) a throw spot exists: from the spot already worked out,
## or by a spot search that is begun (`search.scan`) for the steps to run. Not found: the next one.
func _query(search: ThrowSearch, q: Dictionary) -> void:
	var ctx := search.ctx
	var kind: StringName = q["kind"]
	if _throw.can_lob(
		ctx["space"], ctx["self_pos"], q["spot"], _throw.range_of(kind), know["character_rids"],
	):
		search.found = true
		search.over = true
		return
	if not q["walk"]:
		search.at += 1
		return
	var key := _throw_key(ctx, kind, q["spot"], q["keep_out"])
	var memo := memo_of(ctx)
	var spots: Dictionary = memo["spots"]
	var exists: Dictionary = memo["exists"]
	if spots.has(key) or exists.has(key):
		var yes: bool = not (spots[key] as Dictionary).is_empty() if spots.has(key) else exists[key]
		search.found = yes
		search.over = yes
		search.at += 1
		return
	search.key = key
	search.scan = ThrowScan.new(
		_tactics,
		ctx,
		_throw_aim(ctx, kind, q["spot"], q["keep_out"]),
		know["character_rids"],
		(memo["points"] as Dictionary).get(key),
	)


## What a decision's throw spots for one aim are keyed by: where the NPC stands, the burst spot,
## the reach of the kind and the room kept out of (a frag and a stun of the same reach share).
func _throw_key(ctx: Dictionary, kind: StringName, spot: Vector2, keep_out: Rect2) -> Array:
	return [ctx["self_pos"], spot, _throw.reach_of(kind), keep_out]


## The aim a throw spot is searched for: the burst `spot`, the reach of `kind`, the room kept out
## of, the lob from a candidate and the walk to it.
func _throw_aim(ctx: Dictionary, kind: StringName, spot: Vector2, keep_out: Rect2) -> ThrowAim:
	var space = ctx["space"]
	var rids: Array = know["character_rids"]
	var aim := ThrowAim.new()
	aim.spot = spot
	aim.reach = _throw.reach_of(kind)
	aim.keep_out = keep_out
	aim.lob = func(p: Vector2) -> bool:
		# What a lob is judged on is the spot and the burst, not the kind thrown.
		var key := Vector4(p.x, p.y, spot.x, spot.y)
		var kept: Variant = _tactics.recall(ctx, "lobs", key)
		if kept != null:
			return kept
		return _tactics.remember(
			ctx, "lobs", key, _throw.throw_clear_on_arrival(space, p, spot, rids)
		)
	aim.route = func(p: Vector2) -> Dictionary: return _throw_walk(ctx, p)
	return aim


## The candidate throw points for `aim`, found once per decision and key.
func _candidates(ctx: Dictionary, aim: ThrowAim, key: Array) -> Array:
	var points: Dictionary = memo_of(ctx)["points"]
	if not points.has(key):
		var scan := ThrowScan.new(_tactics, ctx, aim, know["character_rids"])
		while not scan.candidates_done:
			scan.step(ThrowScan.WHOLE)
		points[key] = scan.points
	return points[key]


## Whether the NPC, throwing a grenade of `kind` and `radius` onto `spot` from `from`, would be in
## its danger zone there with no way to get safe before the fuse is out (`AgentThrow.has_escape`
## finds no reachable spot or cover in time).
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
	return not _throw.has_escape(space, ctx["map"], threat, runner, rids)


## The walk to throw spot `p` as the NPC would walk it (agent_door_views.gd `walk_route`: round the
## doorway views when it would take that, E18), and whether the entry guard would stop it on the way
## (`detour`): a doorway into a room not cleared that it crosses (E9), or a doorway view it comes
## into with no way round it (E15), read for a held stack's member from the outer side of the held
## room's doorway it stands in (the knowledge's `keep_out`, D38). `{ path, len, detour }`. The guard
## runs only where doorway views are kept out of (`AgentDoorViews.avoid_views`: tactical entry and
## the guard on).
func _throw_walk(ctx: Dictionary, p: Vector2) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var way: Dictionary = _views.walk_route(self_pos, p, ctx["world"])
	var detour := false
	if _views.avoid_views:
		var cleared := func(key: String) -> bool:
			return _memory.age_of(&"cleared_room", "key", key) <= _v.tuning.memory.search_ttl
		var held := String(know["keep_out"])
		var ahead: Dictionary = _views.threshold_ahead(way["path"], self_pos, cleared, INF, held)
		var crossed: bool = not way["doors"] and not (way["views"] as Array).is_empty()
		detour = not ahead.is_empty() or crossed
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
