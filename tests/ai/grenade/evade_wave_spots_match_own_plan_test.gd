extends GameTest
## G16, an evade wave: several NPCs plan their escape from one grenade on one physics frame, and
## what depends on the burst alone (the candidates round it, their spots on the navmesh, each spot's
## verdict) is worked out once and shared among them (agent_throw.gd `_shared_burst`). Sharing it
## must not change any spot: each NPC runs where its own plan, made by itself from scratch, would
## send it. Five defenders stand in the hall of the furnished terrace house round where an ally
## throws a frag; they see it fly and plan together. On every frame one of them makes a new plan,
## its spot is checked against the plain search (every candidate snapped, judged and routed, nothing
## shared) run for it on that same frame, from where it stood when it planned.
##
## The plain search's inputs are the ones the NPC planned with: its position, its pace and the fuse
## are read at the start of the frame (the NPC plans in its controller, before its body moves and
## before the grenade, added to the world after it, ticks), the grenade's spot is the one the NPC
## knows (`debug_grenades`), and the search runs after every body has processed, before the physics
## step, so the walls, the furniture and the navigation map are the ones the NPC's plan saw.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
## Where the frag is thrown: the middle of the hall, among the defenders.
const LANDING := Vector2(420, 415)
## The defenders round it (inside the frag's zone and within `hear_grenade` of it), each looking
## toward the thrower, so they all see the frag leave its hand and plan together: the wave. (One
## looking away learns of it only when it lands, frames later, alone.)
const DEFENDERS := {
	&"d1": [Vector2(300, 400), Vector2.RIGHT],
	&"d2": [Vector2(360, 445), Vector2.RIGHT],
	&"d3": [Vector2(490, 395), Vector2.RIGHT],
	&"d4": [Vector2(550, 445), Vector2.RIGHT],
	&"d5": [Vector2(610, 410), Vector2.RIGHT],
}
## How many defenders must make a plan on one same frame: the wave whose shared work is checked.
const WAVE := 3


func describe() -> Dictionary:
	return {
		"name": "Every NPC in an evade wave runs to the spot its own plan picks",
		"description": "Five defenders round a frag thrown into the hall plan their escape "
			+ "together; every plan's spot equals the plain search's (nothing shared) for that "
			+ "NPC on that frame, and at least three plan on one frame.",
		"tags": ["ai", "grenade", "evade", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	for id: StringName in DEFENDERS:
		s.actor(id, &"defender", DEFENDERS[id][0], { "facing": DEFENDERS[id][1] })
	# The thrower is on the defenders' side: nobody fights, and the evade (a reflex for any grenade
	# in whose zone an NPC stands) is all that happens.
	s.actor(
		&"thrower",
		&"puppet",
		Vector2(780, 415),
		{ "faction": &"defender", "max_health": 1_000_000.0, "movement:aim_point": LANDING },
	)


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag"):
		return
	var npcs: Array = DEFENDERS.keys().map(func(id: StringName) -> Node: return t.actor(id))
	var ctx := {
		"npcs": npcs,
		"space": thrower.get_world_2d().direct_space_state,
		"map": thrower.get_world_2d().navigation_map,
		# npc -> its AgentThrow: its heights, the grenades it knows the numbers of, its pace
		"own": _own_throws(npcs),
	}
	await t.seconds(0.6)

	ctx["start"] = {}  # the frame's start: { frame, fuse, npc -> { from, speed } }
	ctx["last"] = {}  # npc -> the evade spot it held at the end of the last frame
	ctx["checked"] = []  # { npc, frame, spot, plain }
	t.world.add_child(_late_probe(t, ctx))

	if not await _throw_frag(t, ctx):
		return
	_check_plans(t, ctx["checked"])


## Each NPC's own AgentThrow, bound to its body, with its controller's evade margin.
func _own_throws(npcs: Array) -> Dictionary:
	var own := {}
	for npc: Node in npcs:
		var g = AgentThrow.new()
		g.vision = AgentVision.new()
		g.bind(npc)
		var brain := TestContext.controller_of(npc)
		g.evade_margin = float(brain.get_indexed("tuning:grenades:evade_margin"))
		own[npc] = g
	return own


## The probe that runs after every NPC's physics frame: on a frame the grenade's start was noted,
## each NPC's plan is checked.
func _late_probe(t: TestContext, ctx: Dictionary) -> LateProbe:
	var start: Dictionary = ctx["start"]
	var npcs: Array = ctx["npcs"]
	var late := LateProbe.new()
	late.process_physics_priority = 1000
	late.each = func() -> void:
		if start.get("frame", -1) != Engine.get_physics_frames():
			return
		var live := Probe.live(t)
		if live.is_empty():
			return
		for npc: Node in npcs:
			_check_plan(t, ctx, npc, live[0])
	return late


## A new evade spot `npc` holds this frame, kept in `ctx.checked` beside its own plain search's.
func _check_plan(t: TestContext, ctx: Dictionary, npc: Node, grenade: Node) -> void:
	var brain := TestContext.controller_of(npc)
	var seen: Dictionary = Probe.grenades(brain)
	var spot: Vector2 = seen.get("escape", Vector2.INF)
	var last: Dictionary = ctx["last"]
	if spot == last.get(npc, Vector2.INF):
		return
	last[npc] = spot
	var known: Array = seen.get("known", [])
	if known.is_empty():
		return
	var plain := _plain_for(t, ctx, npc, grenade, known)
	var checked: Array = ctx["checked"]
	checked.append({
		"npc": npc.name,
		"frame": ctx["start"]["frame"],
		"spot": spot,
		"plain": plain["spot"],
	})


## The plain search for `npc`, from where it stood and how fast it ran as the frame began.
func _plain_for(
		t: TestContext,
		ctx: Dictionary,
		npc: Node,
		grenade: Node,
		known: Array,
) -> Dictionary:
	var g = ctx["own"][npc]
	var space: PhysicsDirectSpaceState2D = ctx["space"]
	var map: RID = ctx["map"]
	var start: Dictionary = ctx["start"]
	g.learn_carried()
	g.learn_body()
	g.learn(grenade.call("throw_stats"))
	var kind: StringName = known[0]["kind"]
	var at: Dictionary = start[npc]
	var search := { "space": space, "map": map, "exclude": Probe.character_rids(t) }
	var threat := _threat(kind, g.radius_of(kind), known[0]["point"], float(start["fuse"]))
	var plain := _plain_escape(g, search, threat, _runner(at["from"], float(at["speed"])))
	return plain


## The grenade as the escape takes it.
func _threat(kind: StringName, radius: float, burst: Vector2, fuse: float) -> GrenadeThreat:
	var threat := GrenadeThreat.new()
	threat.kind = kind
	threat.radius = radius
	threat.burst = burst
	threat.fuse_left = fuse
	return threat


## The runner as the escape takes it.
func _runner(from: Vector2, speed: float) -> GrenadeRunner:
	var runner := GrenadeRunner.new()
	runner.from = from
	runner.speed = speed
	return runner


## The thrower lobs its frag at the landing; until it goes off, each frame's start is noted.
func _throw_frag(t: TestContext, ctx: Dictionary) -> bool:
	var puppet := t.puppet(&"thrower")
	puppet.select_slot(Probe.FRAG)
	puppet.aim_at(LANDING)
	await t.seconds(0.4)
	puppet.aim_at(LANDING)
	await t.frames(3)
	puppet.shoot()
	var deadline := t.time + 6.0
	while t.time < deadline and Probe.booms(t, &"frag").is_empty():
		await t.frames(1)
		_note_start(t, ctx)
	return t.require(not Probe.booms(t, &"frag").is_empty(), "the frag went off")


## The frame's start: its frame, the live grenade's fuse, and each NPC's place and pace.
func _note_start(t: TestContext, ctx: Dictionary) -> void:
	var live := Probe.live(t)
	var start: Dictionary = ctx["start"]
	var own: Dictionary = ctx["own"]
	start.clear()  # (Filled in place: the late probe's lambda holds this dictionary.)
	start["frame"] = Engine.get_physics_frames()
	start["fuse"] = float(live[0].call("fuse_left")) if not live.is_empty() else 0.0
	for npc: Node in ctx["npcs"]:
		start[npc] = { "from": (npc as Node2D).global_position, "speed": own[npc].run_speed() }


## Every defender planned, enough of them on one frame, and every plan matched its plain search.
func _check_plans(t: TestContext, checked: Array) -> void:
	var planned := {}    # npc name -> true
	var per_frame := {}  # frame -> how many NPCs made a plan on it
	var differing: Array = []
	for c: Dictionary in checked:
		if c["spot"] != Vector2.INF:
			planned[c["npc"]] = true
		per_frame[c["frame"]] = int(per_frame.get(c["frame"], 0)) + 1
		if c["spot"] != c["plain"]:
			differing.append("%s on frame %d ran to %s, its own plan picks %s"
					% [c["npc"], c["frame"], c["spot"].round(), c["plain"].round()])
	var wave: int = per_frame.values().max() if not per_frame.is_empty() else 0
	t.check(
		planned.size() == DEFENDERS.size(),
		"every defender planned an escape with a spot (%s)" % str(planned.keys()),
	)
	t.check(
		wave >= WAVE,
		"at least %d defenders planned on one frame (the most on one frame: %d; %d plans checked)"
			% [WAVE, wave, checked.size()],
	)
	t.check(
		differing.is_empty(),
		"%d of %d plans differ from the NPC's own plain search: %s"
			% [differing.size(), checked.size(), differing.slice(0, 3)],
	)


## `AgentThrow.escape` with nothing shared: every candidate snapped, judged and routed, as
## `ai/grenade/escape_spot_matches_plain` pins it. `search` is the search's world (`space`, `map`,
## `exclude`).
func _plain_escape(
		g: AgentThrow,
		search: Dictionary,
		threat: GrenadeThreat,
		runner: GrenadeRunner,
) -> Dictionary:
	var spots := _plain_spots(g, search, threat, runner.from)
	var allowed := maxf(threat.fuse_left - AgentThrow.ARRIVE_MARGIN, 0.0) * runner.speed
	return _plain_best(search["map"], spots, runner.from, allowed)


## Every candidate of the plain search snapped and judged: `{ spot, crouch }` for each that lands
## out of the burst's zone or shielded from it, `crouch` when only a crouched body is shielded.
func _plain_spots(
		g: AgentThrow,
		search: Dictionary,
		threat: GrenadeThreat,
		from: Vector2,
) -> Array:
	var map: RID = search["map"]
	var zone := {
		"burst": threat.burst,
		"out_r": g._zone_radius(threat.kind, threat.radius) + AgentThrow.OUTSIDE_SLACK,
		"reach": g.cover_reach(threat.kind),
	}
	var spots: Array = []
	# The candidates' grenade as the plain search builds it: its kind, radius and burst.
	var around := GrenadeThreat.new()
	around.kind = threat.kind
	around.radius = threat.radius
	around.burst = threat.burst
	for p in g._candidates(search["space"], around, from, search["exclude"]):
		var q := NavBuilder.snap(map, p)
		if q.distance_to(p) > AgentThrow.SNAP_TOLERANCE:
			continue
		var spot := _plain_spot(g, search, q, zone)
		if not spot.is_empty():
			spots.append(spot)
	return spots


## The plain search's verdict on the snapped candidate `q` for the burst `zone` (`burst`, `out_r`,
## `reach`): `{ spot, crouch }`, `crouch` when only a crouched body is shielded there; `{}` when it
## is inside the zone and shielded neither way.
func _plain_spot(g: AgentThrow, search: Dictionary, q: Vector2, zone: Dictionary) -> Dictionary:
	var space: PhysicsDirectSpaceState2D = search["space"]
	var exclude: Array = search["exclude"]
	var burst: Vector2 = zone["burst"]
	var reach: float = zone["reach"]
	var crouch := false
	if (q.distance_to(burst) < zone["out_r"]
			and not g._covered(
				space,
				burst,
				q,
				AgentThrow._cover_rule(g.stand_height(), exclude, reach),
			)):
		if not g._covered(
			space,
			burst,
			q,
			AgentThrow._cover_rule(g.crouch_height(), exclude, reach),
		):
			return {}
		crouch = true
	return { "spot": q, "crouch": crouch }


## Of `spots`, the one with the shortest route from `from` within `allowed` px:
## `{ spot, crouch, route }`, `spot` INF when none is in time.
func _plain_best(map: RID, spots: Array, from: Vector2, allowed: float) -> Dictionary:
	var best := { "spot": Vector2.INF, "crouch": false, "route": INF }
	for s: Dictionary in spots:
		var length := NavBuilder.path_length(NavBuilder.route(map, from, s["spot"]))
		if length <= allowed and length < best["route"]:
			best = { "spot": s["spot"], "crouch": s["crouch"], "route": length }
	return best


## Runs after every other node on each physics frame, before the physics step.
class LateProbe extends Node:
	var each: Callable

	func _physics_process(_delta: float) -> void:
		each.call()
