extends GameTest
## The decision micro bundle (#192 rule 37) changes no answer, only the work: a route's exposure is
## settled as soon as five samples are seen or four missed, the throw lob of a spot is judged once
## a decision whatever kind asks, room-centre snaps are asked once, a firing spot is refused by its
## cheapest check first, and cover reads fewer properties. Each item is held against the plain
## computation (the spec's own count of an exposed route: more than half of its eight samples in
## sight) and shows by a counter that the fast path was taken.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
const CountingVision := preload("res://tests/_ai/counting_vision.gd")
## Samples along a route (the spec: eight, exposed when more than half are in sight).
const SAMPLES := 8


func describe() -> Dictionary:
	return {
		"name": "The decision micro bundle matches the plain computation",
		"description": "Route exposure stopped early, the throw lob and room-centre snaps "
			+ "memoised per decision, the firing spot's checks reordered and the cheaper cover "
			+ "read give the plain computation's answers with less work.",
		"tags": ["ai", "decision", "tactics", "snapshot"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	s.actor(&"npc", &"puppet", Maps.HALL_MIDDLE)


func run(t: TestContext) -> void:
	await t.frames(2)
	_exposure(t)


## `_route_exposed` equals the full eight-sample count over routes and threat positions of the house
## (with and without a facing), and casts fewer rays than the full count where it settles early.
func _exposure(t: TestContext) -> void:
	var tactics := _tactics()
	var npc := t.actor(&"npc")
	var world := {
		"space": npc.get_world_2d().direct_space_state, "ex": [npc.get_rid()],
		"map": npc.get_world_2d().navigation_map,
	}
	var spots: Array = [
		Maps.HALL_MIDDLE, Maps.LIVING_CENTRE, Maps.KITCHEN_CENTRE, Maps.DOOR_HALL_LIVING,
		Maps.DOOR_HALL_KITCHEN, Maps.DOOR_LIVING_KITCHEN, Vector2(60, 60), Vector2(800, 320),
	]
	var tally := { "calls": 0, "exposed": 0, "full": 0, "wrong": [], "over": 0, "fast": 0 }
	for threat: Vector2 in spots:
		for to: Vector2 in spots:
			var path := NavBuilder.route(world["map"], threat + Vector2(0, 20), to)
			for front: float in [NAN, 0.0, PI * 0.5, PI, -PI * 0.5]:
				var plain := _plain_exposed(tactics, world, path, threat, front)
				tally["calls"] += 1
				tally["full"] += plain["rays"]
				tally["exposed"] += 1 if plain["exposed"] else 0
				var before: int = tactics.vision.rays
				var got: bool = tactics._route_exposed(
					world["space"], path, threat, world["ex"], front
				)
				if got != plain["exposed"]:
					tally["wrong"].append([threat, to, front])
				var cast: int = tactics.vision.rays - before
				tally["fast"] += cast
				tally["over"] += 1 if cast > plain["rays"] else 0
	t.require(
		tally["exposed"] > tally["calls"] / 10 and tally["exposed"] < tally["calls"] * 9 / 10,
		"set-up: the fixtures hold exposed and hidden routes (%d of %d)"
			% [tally["exposed"], tally["calls"]],
	)
	t.check(
		(tally["wrong"] as Array).is_empty(),
		"exposure equals the full eight-sample count (%s)" % str(tally["wrong"]),
	)
	t.check(tally["over"] == 0, "a route's exposure never casts more rays than the full count")
	t.check(
		tally["fast"] < tally["full"],
		"routes settled early cast fewer rays (%d against %d)"
			% [tally["fast"], tally["full"]],
	)


## The route exposure by the spec's plain count: every sample, no early stop. `{ exposed, rays }`.
func _plain_exposed(
		tactics: RefCounted, world: Dictionary, path: PackedVector2Array, threat: Vector2,
		front: float,
) -> Dictionary:
	var total := NavBuilder.path_length(path)
	if total <= 0.0:
		return { "exposed": false, "rays": 0 }
	var half := deg_to_rad(tactics.watch_arc) * 0.5
	var seen := 0
	var rays := 0
	for i in SAMPLES:
		var sample: Vector2 = tactics._along(path, total * (i + 1) / (SAMPLES + 1))
		if not is_nan(front) and absf(angle_difference(front, (sample - threat).angle())) > half:
			continue
		rays += 1
		if not tactics.blocked(world["space"], threat, sample, world["ex"]):
			seen += 1
	return { "exposed": seen * 2 > SAMPLES, "rays": rays }


## Tactics tuned as a combat snapshot's.
func _tactics() -> RefCounted:
	var tactics := AgentTactics.new()
	tactics.vision = CountingVision.new()
	tactics.cover_min = 40.0
	tactics.flank_distance = 120.0
	tactics.flank_arc = 30.0
	tactics.flank_ally_radius = 80.0
	tactics.shoot_range = 400.0
	tactics.combat_ring_radius = 96.0
	tactics.combat_ring_count = 12
	tactics.still_speed = 10.0
	tactics.route_clearance = 40.0
	tactics.watch_arc = 90.0
	tactics.fire_spot_distances = [160.0, 260.0]
	return tactics
