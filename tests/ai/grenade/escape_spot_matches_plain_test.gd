extends GameTest
## G16's escape spot (agent_throw.gd `escape`) snaps each candidate, judges each spot it lands on
## and routes each spot once, where the plain loop does all three for every candidate (the standing
## and the crouching probe often meet the same wall, so many candidates are the same point). This
## pins its answer to the plain loop, over frags and stuns going off all round a furnished house
## with the NPC at many places, so the spot an NPC runs to, whether it crouches and the length of
## its route are unchanged.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const SEED := 1717
const CASES := 60
## How far (px) from the burst the NPC stands in each case: inside the zone of either kind.
const NEAR := 220.0


func describe() -> Dictionary:
	return {
		"name": "The escape spot is the same as the plain search finds",
		"description": "AgentThrow.escape gives the same spot, crouch and route length as the loop "
			+ "that snaps, judges and routes every candidate, for frags and stuns all over a "
			+ "furnished house.",
		"tags": ["ai", "grenade", "evade"],
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
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var ctx := {
		"geometry": geometry,
		"space": npc.get_world_2d().direct_space_state,
		"map": npc.get_world_2d().navigation_map,
		"exclude": GrenadeAi.character_rids(t),
		"rng": rng,
	}
	var rooms: Array = t.rooms
	var tally := {
		"compared": 0, "found": 0, "existence": 0, "out_zone_routes": -1, "differing": [],
	}
	for n in CASES:
		var room: Dictionary = rooms[n % rooms.size()]
		_compare_case(ctx, tally, room["rect"])
	_fixed_cases(ctx, tally)
	var compared: int = tally["compared"]
	var found: int = tally["found"]
	var differing: Array = tally["differing"]
	t.check(
		compared == CASES * 2 and found >= CASES / 2.0,
		"escapes compared (%d, %d with a spot)" % [compared, found],
	)
	t.check(
		tally["existence"] == CASES * 2 + 6,
		"existence answers compared, including the six fixed fixtures",
	)
	t.check(
		tally["out_zone_routes"] == 1,
		"the out-of-zone existence answer stops after its first safe candidate",
	)
	t.check(
		differing.is_empty(),
		"%d of %d escapes differ from the plain search: %s"
			% [differing.size(), compared, differing.slice(0, 3)],
	)


## One drawn case in room `rect`: a burst and a runner near it, each kind of grenade compared.
func _compare_case(ctx: Dictionary, tally: Dictionary, rect: Rect2) -> void:
	var map: RID = ctx["map"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var burst := NavBuilder.snap(
		map,
		rect.position + Vector2(rng.randf(), rng.randf()) * rect.size,
	)
	var from := NavBuilder.snap(
		map,
		burst + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, NEAR),
	)
	for kind in [&"frag", &"stun"]:
		_compare_kind(ctx, tally, kind, burst, from)


## The escape from a `kind` grenade bursting at `burst`, for a runner at `from`, against the plain
## search; counted in `tally`, a difference listed there.
func _compare_kind(
		ctx: Dictionary,
		tally: Dictionary,
		kind: StringName,
		burst: Vector2,
		from: Vector2,
) -> void:
	var geometry = ctx["geometry"]
	var space: PhysicsDirectSpaceState2D = ctx["space"]
	var map: RID = ctx["map"]
	var exclude: Array = ctx["exclude"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var radius: float = geometry.radius_of(kind)
	var fuse := rng.randf_range(0.6, 3.0)
	var speed := rng.randf_range(90.0, 260.0)
	var fast: Dictionary = geometry.escape(
		space,
		map,
		GrenadeAi.escape_threat(kind, radius, burst, fuse),
		GrenadeAi.escape_runner(from, speed),
		exclude,
	)
	var plain := GrenadeAi.plain_escape(
		geometry,
		{ "space": space, "map": map, "exclude": exclude },
		GrenadeAi.escape_threat(kind, radius, burst, fuse),
		GrenadeAi.escape_runner(from, speed),
	)
	tally["compared"] += 1
	tally["found"] += 1 if fast["spot"] != Vector2.INF else 0
	if fast != plain:
		tally["differing"].append("%s at %s from %s: %s, plain %s"
				% [kind, burst.round(), from.round(), fast, plain])
	_compare_existence(ctx, tally, {
		"kind": kind, "burst": burst, "from": from, "fuse": fuse, "speed": speed,
	})


## Six named arrangements of the same existence question, including immediate safety, no time to
## move and candidates that snap onto one another.
func _fixed_cases(ctx: Dictionary, tally: Dictionary) -> void:
	var map: RID = ctx["map"]
	var cases: Array = [
		{ "label": "covered", "kind": &"frag", "burst": Vector2(650, 50),
			"from": Vector2(650, 260), "fuse": 1.0, "speed": 120.0 },
		{ "label": "out-of-zone", "kind": &"frag", "burst": Maps.HALL_MIDDLE,
			"from": Maps.GARDEN, "fuse": 1.0, "speed": 120.0 },
		{ "label": "reachable", "kind": &"frag", "burst": Maps.LIVING_CENTRE,
			"from": Vector2(300, 250), "fuse": 3.0, "speed": 200.0 },
		{ "label": "unreachable", "kind": &"frag", "burst": Maps.LIVING_CENTRE,
			"from": Vector2(260, 250), "fuse": 0.6, "speed": 1.0 },
		{ "label": "duplicate-candidate", "kind": &"stun", "burst": Maps.KITCHEN_CENTRE,
			"from": Maps.HALL_MIDDLE, "fuse": 3.0, "speed": 200.0 },
		{ "label": "no-escape", "kind": &"frag", "burst": Maps.HALL_MIDDLE,
			"from": Maps.HALL_MIDDLE, "fuse": 0.1, "speed": 0.0 },
	]
	for c in cases:
		c["burst"] = NavBuilder.snap(map, c["burst"])
		c["from"] = NavBuilder.snap(map, c["from"])
		_compare_existence(ctx, tally, c)
		if c["label"] == "out-of-zone":
			tally["out_zone_routes"] = ctx["geometry"].escape_route_queries


## Compare only whether a safe, reachable escape exists with the full plain search's answer.
func _compare_existence(ctx: Dictionary, tally: Dictionary, c: Dictionary) -> void:
	var geometry = ctx["geometry"]
	var kind: StringName = c["kind"]
	var burst: Vector2 = c["burst"]
	var from: Vector2 = c["from"]
	var threat := GrenadeAi.escape_threat(kind, geometry.radius_of(kind), burst, c["fuse"])
	var runner := GrenadeAi.escape_runner(from, c["speed"])
	var exists: bool = geometry.has_escape(
		ctx["space"], ctx["map"], threat, runner, ctx["exclude"]
	)
	var plain := GrenadeAi.plain_escape(
		geometry,
		{ "space": ctx["space"], "map": ctx["map"], "exclude": ctx["exclude"] },
		threat,
		runner,
	)
	tally["existence"] += 1
	if exists != (plain["spot"] != Vector2.INF):
		tally["differing"].append("existence %s %s at %s from %s: %s, plain %s"
				% [c.get("label", ""), kind, burst.round(), from.round(), exists, plain])
