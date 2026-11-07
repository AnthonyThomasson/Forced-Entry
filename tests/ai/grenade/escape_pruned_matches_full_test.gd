extends GameTest
## G16's escape spot, pruned (#192 rule 30): `AgentThrow.escape` measures the routes to the safe
## candidates nearest the runner first (by straight line) and stops once the next one lies past
## both the best route found and the distance it may run in time, since a route is never shorter
## than its straight line. The answer must be the one measuring every safe candidate gives (spot,
## crouch and route, the first in the candidate order winning a tie), and over an open floor and
## through a doorway it measures fewer routes. `escape_routes_measured` counts them.
##
## Five fixtures in the furnished terrace house, each a burst and a runner: open floor (the living
## room), a wall corner (the runner round the kitchen's wall from the burst), a doorway (the runner
## in the living-room doorway, the burst in the kitchen), cover furniture (the runner by the
## cabinet in the hall) and no spot in time (no fuse to run in). The reference is the plain search
## of `tests/_ai/grenade_ai_probe.gd` (`plain_escape`: every candidate snapped, judged and routed).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
## How many runners off the navmesh `_check_off_mesh` draws.
const OFF_MESH_CASES := 300
## burst, runner, fuse left (s), pace (px/s), and whether the pruned search must measure fewer
## routes than there are safe spots.
const FIXTURES := [
	{ "label": "open floor", "kind": &"frag", "burst": Vector2(260, 190),
		"from": Vector2(300, 250), "fuse": 3.0, "speed": 200.0, "fewer": true },
	{ "label": "open floor, stun", "kind": &"stun", "burst": Vector2(260, 190),
		"from": Vector2(300, 250), "fuse": 3.0, "speed": 200.0, "fewer": true },
	{ "label": "wall corner", "kind": &"frag", "burst": Vector2(660, 190),
		"from": Vector2(470, 340), "fuse": 3.0, "speed": 200.0, "fewer": false },
	{ "label": "doorway", "kind": &"frag", "burst": Vector2(660, 190),
		"from": Vector2(470, 150), "fuse": 3.0, "speed": 200.0, "fewer": true },
	{ "label": "cover furniture", "kind": &"frag", "burst": Vector2(420, 415),
		"from": Vector2(470, 410), "fuse": 3.0, "speed": 200.0, "fewer": false },
	{ "label": "no spot in time", "kind": &"frag", "burst": Vector2(420, 415),
		"from": Vector2(420, 415), "fuse": 0.1, "speed": 0.0, "fewer": false },
]


func describe() -> Dictionary:
	return {
		"name": "The pruned escape search finds what measuring every candidate finds",
		"description": "AgentThrow.escape, measuring routes nearest-first and stopping past the "
			+ "best, gives the same spot, crouch and route as measuring every safe candidate "
			+ "over open floor, a wall corner, a doorway, cover furniture and no spot in time, "
			+ "and measures fewer routes over open floor and a doorway.",
		"tags": ["ai", "grenade", "evade", "perf"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	s.actor(&"npc", &"puppet", Maps.HALL_MIDDLE)


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	Probe.arm(npc, 1, 1)
	await t.frames(2)
	var geometry = AgentThrow.new()
	geometry.vision = AgentVision.new()
	geometry.bind(npc)
	geometry.learn_carried()
	geometry.learn_body()
	var search := {
		"space": npc.get_world_2d().direct_space_state,
		"map": npc.get_world_2d().navigation_map,
		"exclude": GrenadeAi.character_rids(t),
	}
	var spotted := 0
	for f: Dictionary in FIXTURES:
		spotted += 1 if _check_fixture(t, geometry, search, f) else 0
	t.check(spotted >= 3, "at least three fixtures found a spot in time (%d)" % spotted)
	_check_off_mesh(t, geometry, search["map"])
	_check_tie(t, geometry, search["map"])


## One fixture: the pruned answer against the plain one, and the routes measured; true when it
## found a spot.
func _check_fixture(
		t: TestContext,
		geometry: AgentThrow,
		search: Dictionary,
		f: Dictionary,
) -> bool:
	var map: RID = search["map"]
	var kind: StringName = f["kind"]
	var threat := GrenadeAi.escape_threat(
		kind, geometry.radius_of(kind), NavBuilder.snap(map, f["burst"]), f["fuse"],
	)
	var runner := GrenadeAi.escape_runner(NavBuilder.snap(map, f["from"]), f["speed"])
	var pruned: Dictionary = geometry.escape(
		search["space"], map, threat, runner, search["exclude"],
	)
	var measured = geometry.get(&"escape_routes_measured")
	var tally := {}
	var plain := GrenadeAi.plain_escape(geometry, search, threat, runner, tally)
	var safe: int = tally["safe"]
	var label: String = f["label"]
	t.check(
		pruned == plain,
		"%s: the pruned escape is %s, measuring every candidate gives %s" % [label, pruned, plain],
	)
	t.check(
		measured is int and measured <= safe,
		"%s: routes measured (%s) are at most the safe spots (%d)" % [label, measured, safe],
	)
	if f["fewer"]:
		t.check(
			measured is int and measured < safe,
			"%s: fewer routes measured (%s) than the safe spots there are (%d)"
				% [label, measured, safe],
		)
	return pruned["spot"] != Vector2.INF


## A runner standing off the navmesh (a character squeezed into a wall's thickness or a furniture
## hole): a path starts from the mesh point nearest it, and one may end `ROUTE_REACH` short of its
## spot, so a route can be shorter than the straight line from where the runner stands. Over drawn
## runners that far off the mesh and drawn safe spots, the pruned search still picks what measuring
## every spot picks.
func _check_off_mesh(t: TestContext, geometry: AgentThrow, map: RID) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2929
	var differing: Array = []
	var cases := 0
	while cases < OFF_MESH_CASES:
		var on := NavBuilder.snap(map, Vector2(rng.randf_range(0, 840), rng.randf_range(0, 470)))
		var from := on + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(8.0, 30.0)
		if NavBuilder.snap(map, from).distance_to(from) < 4.0:
			continue
		cases += 1
		var spots: Array = []
		for i in 8:
			var near := from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 320.0)
			spots.append({ "spot": NavBuilder.snap(map, near), "crouch": i % 2 == 0 })
		var allowed := rng.randf_range(80.0, 500.0)
		var pruned: Dictionary = geometry._nearest_in_time(map, from, spots, allowed)
		var full := _measure_every(map, from, spots, allowed)
		if pruned != full:
			differing.append("from %s: %s, every spot %s" % [from.round(), pruned, full])
	t.check(
		differing.is_empty(),
		"%d of %d off-mesh runners differ from measuring every spot: %s"
			% [differing.size(), OFF_MESH_CASES, differing.slice(0, 2)],
	)


## One spot listed twice, once crouched and once not: the routes are exactly equal and the one
## listed first wins, in either order.
func _check_tie(t: TestContext, geometry: AgentThrow, map: RID) -> void:
	var from := NavBuilder.snap(map, Maps.HALL_MIDDLE)
	var at := NavBuilder.snap(map, from + Vector2(100, 0))
	var standing := { "spot": at, "crouch": false }
	var crouched := { "spot": at, "crouch": true }
	for spots: Array in [[standing, crouched], [crouched, standing]]:
		var pruned: Dictionary = geometry._nearest_in_time(map, from, spots, 300.0)
		t.check(
			pruned["spot"] == at and pruned["crouch"] == spots[0]["crouch"],
			"equal routes: the first listed spot wins (%s of %s)" % [pruned, spots],
		)


## The plain search over `spots` (`{ spot, crouch }`): every spot's route measured, the shortest
## within `allowed` px that ends on its spot (`AgentThrow.ROUTE_REACH`), the first listed on a tie.
func _measure_every(map: RID, from: Vector2, spots: Array, allowed: float) -> Dictionary:
	var best := { "spot": Vector2.INF, "crouch": false, "route": INF }
	for s: Dictionary in spots:
		var path := NavBuilder.route(map, from, s["spot"])
		if path[path.size() - 1].distance_to(s["spot"]) > 2.0:
			continue
		var length := NavBuilder.path_length(path)
		if length <= allowed and length < best["route"]:
			best = { "spot": s["spot"], "crouch": s["crouch"], "route": length }
	return best
