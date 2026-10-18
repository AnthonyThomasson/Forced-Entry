extends GameTest

## G16, an evade wave: several NPCs plan their escape from one grenade on one physics frame, and what depends on the burst alone (the
## candidates round it, their spots on the navmesh, each spot's verdict) is worked out once and shared among them (agent_throw.gd
## `_shared_burst`). Sharing it must not change any spot: each NPC runs where its own plan, made by itself from scratch, would send it.
## Five defenders stand in the hall of the furnished terrace house round where an ally throws a frag; they see it fly
## and plan together. On every frame one of them makes a new plan, its spot is checked against the plain search (every candidate
## snapped, judged and routed, nothing shared) run for it on that same frame, from where it stood when it planned.
##
## The plain search's inputs are the ones the NPC planned with: its position, its pace and the fuse are read at the start of the frame
## (the NPC plans in its controller, before its body moves and before the grenade, added to the world after it, ticks), the grenade's
## spot is the one the NPC knows (`debug_grenades`), and the search runs after every body has processed, before the physics step, so
## the walls, the furniture and the navigation map are the ones the NPC's plan saw.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")

## Where the frag is thrown: the middle of the hall, among the defenders.
const LANDING := Vector2(420, 415)
## The defenders round it (inside the frag's zone and within `hear_grenade` of it), each looking toward the thrower, so they all see the
## frag leave its hand and plan together: the wave. (One looking away learns of it only when it lands, frames later, alone.)
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
		"description": "Five defenders round a frag thrown into the hall plan their escape together; every plan's spot equals the plain search's (nothing shared) for that NPC on that frame, and at least three plan on one frame.",
		"tags": ["ai", "grenade", "evade", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	for id: StringName in DEFENDERS:
		s.actor(id, &"defender", DEFENDERS[id][0], { "facing": DEFENDERS[id][1] })
	# The thrower is on the defenders' side: nobody fights, and the evade (a reflex for any grenade in whose zone an NPC stands) is all
	# that happens.
	s.actor(&"thrower", &"puppet", Vector2(780, 415), { "faction": &"defender", "max_health": 1000000.0, "aim_point": LANDING })


## Runs after every other node on each physics frame, before the physics step.
class LateProbe extends Node:
	var each: Callable

	func _physics_process(_delta: float) -> void:
		each.call()


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag"):
		return
	var npcs: Array = DEFENDERS.keys().map(func(id: StringName) -> Node: return t.actor(id))
	var space: PhysicsDirectSpaceState2D = thrower.get_world_2d().direct_space_state
	var map: RID = thrower.get_world_2d().navigation_map
	var own := {}  # npc -> its AgentThrow: its heights, the grenades it knows the numbers of, its pace
	for npc: Node in npcs:
		var g = AgentThrow.new()
		g.vision = AgentVision.new()
		g.bind(npc)
		g.evade_margin = float(TestContext.controller_of(npc).get("evade_margin"))
		own[npc] = g
	await t.seconds(0.6)

	var start := {}      # the frame's start: { frame, fuse, npc -> { from, speed } }
	var last := {}       # npc -> the evade spot it held at the end of the last frame
	var checked: Array = []  # { npc, frame, spot, plain }
	var late := LateProbe.new()
	late.process_physics_priority = 1000
	late.each = func() -> void:
		if start.get("frame", -1) != Engine.get_physics_frames():
			return
		var live := Probe.live(t)
		if live.is_empty():
			return
		for npc: Node in npcs:
			var brain := TestContext.controller_of(npc)
			var seen: Dictionary = Probe.grenades(brain)
			var spot: Vector2 = seen.get("escape", Vector2.INF)
			if spot == last.get(npc, Vector2.INF):
				continue
			last[npc] = spot
			var known: Array = seen.get("known", [])
			if known.is_empty():
				continue
			var g = own[npc]
			var grenade: Node = live[0]
			g.learn_carried()
			g.learn_body()
			g.learn(grenade.call("throw_stats"))
			var kind: StringName = known[0]["kind"]
			var at: Dictionary = start[npc]
			var plain := _plain_escape(g, space, map, kind, g.radius_of(kind), known[0]["point"], at["from"], float(start["fuse"]),
				float(at["speed"]), Probe.character_rids(t))
			checked.append({ "npc": npc.name, "frame": start["frame"], "spot": spot, "plain": plain["spot"] })
	t.world.add_child(late)

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
		var live := Probe.live(t)
		start.clear()  # (Filled in place: the late probe's lambda holds this dictionary.)
		start["frame"] = Engine.get_physics_frames()
		start["fuse"] = float(live[0].call("fuse_left")) if not live.is_empty() else 0.0
		for npc: Node in npcs:
			start[npc] = { "from": (npc as Node2D).global_position, "speed": own[npc].run_speed() }
	if not t.require(not Probe.booms(t, &"frag").is_empty(), "the frag went off"):
		return

	var planned := {}    # npc name -> true
	var per_frame := {}  # frame -> how many NPCs made a plan on it
	var differing: Array = []
	for c: Dictionary in checked:
		if c["spot"] != Vector2.INF:
			planned[c["npc"]] = true
		per_frame[c["frame"]] = int(per_frame.get(c["frame"], 0)) + 1
		if c["spot"] != c["plain"]:
			differing.append("%s on frame %d ran to %s, its own plan picks %s" % [c["npc"], c["frame"], c["spot"].round(), c["plain"].round()])
	var wave: int = per_frame.values().max() if not per_frame.is_empty() else 0
	t.check(planned.size() == DEFENDERS.size(), "every defender planned an escape with a spot (%s)" % str(planned.keys()))
	t.check(wave >= WAVE, "at least %d defenders planned on one frame (the most on one frame: %d; %d plans checked)" % [WAVE, wave, checked.size()])
	t.check(differing.is_empty(), "%d of %d plans differ from the NPC's own plain search: %s" % [differing.size(), checked.size(), differing.slice(0, 3)])


## `AgentThrow.escape` with nothing shared: every candidate snapped, judged and routed, as `ai/grenade/escape_spot_matches_plain` pins it.
func _plain_escape(g, space, map: RID, kind: StringName, radius: float, burst: Vector2, from: Vector2, fuse_left: float,
		speed: float, exclude: Array) -> Dictionary:
	var out_r: float = g.zone_radius(kind, radius) + AgentThrow.OUTSIDE_SLACK
	var reach: float = g.cover_reach(kind)
	var spots: Array = []
	for p in g._candidates(space, burst, from, out_r, exclude, kind):
		var q := NavBuilder.snap(map, p)
		if q.distance_to(p) > AgentThrow.SNAP_TOLERANCE:
			continue
		var crouch := false
		if q.distance_to(burst) < out_r and not g._covered(space, burst, q, g.stand_height(), exclude, reach):
			if not g._covered(space, burst, q, g.crouch_height(), exclude, reach):
				continue
			crouch = true
		spots.append({ "spot": q, "crouch": crouch })
	var best := { "spot": Vector2.INF, "crouch": false, "route": INF }
	var allowed := maxf(fuse_left - AgentThrow.ARRIVE_MARGIN, 0.0) * speed
	for s: Dictionary in spots:
		var length := NavBuilder.path_length(NavBuilder.route(map, from, s["spot"]))
		if length <= allowed and length < best["route"]:
			best = { "spot": s["spot"], "crouch": s["crouch"], "route": length }
	return best
