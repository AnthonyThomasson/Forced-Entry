extends GameTest
## G16's escape spot (agent_throw.gd `escape`) snaps each candidate, judges each spot it lands on
## and routes each spot once, where the plain loop does all three for every candidate (the standing
## and the crouching probe often meet the same wall, so many candidates are the same point). This
## pins its answer to the plain loop, over frags and stuns going off all round a furnished house
## with the NPC at many places, so the spot an NPC runs to, whether it crouches and the length of
## its route are unchanged. The search stepped a few units at a time (`EscapeSearch.step`, as the
## pool serves it) gives the same answer as the whole one.

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
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var ctx := {
		"geometry": geometry,
		"space": TwinSpace.space_of(npc),
		"map": NavWorld.map_of(npc),
		"exclude": GrenadeAi.character_rids(t),
		"rng": rng,
	}
	var tally := {
		"compared": 0, "found": 0, "steps": 0, "existence": 0, "out_zone_routes": -1,
		"differing": [], "tight": 0, "tight_straight": 0,
	}
	for n in CASES:
		_compare_case(ctx, tally, (t.rooms[n % t.rooms.size()] as Dictionary)["rect"])
	_fixed_cases(ctx, tally)
	_check_tally(t, tally)


## What the cases found.
func _check_tally(t: TestContext, tally: Dictionary) -> void:
	var compared: int = tally["compared"]
	var found: int = tally["found"]
	var differing: Array = tally["differing"]
	t.check(
		compared == CASES * 2 and found >= CASES / 2.0,
		"escapes compared (%d, %d with a spot)" % [compared, found],
	)
	t.check(
		int(tally["tight"]) >= CASES / 2.0 and int(tally["tight_straight"]) >= 10,
		"premise: winners compared at the edge of the run allowed (%d; %d on a straight route)"
			% [tally["tight"], tally["tight_straight"]],
	)
	t.check(
		tally["existence"] == CASES * 2 + 6,
		"existence answers compared, including the six fixed fixtures",
	)
	t.check(
		int(tally["steps"]) > compared,
		"premise: a search takes several steps of 3 units (%d steps, %d searches)"
			% [tally["steps"], compared],
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
	var space: PhysicsDirectSpaceState3D = ctx["space"]
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
	_compare_sliced(ctx, tally, fast, [
		GrenadeAi.escape_threat(kind, radius, burst, fuse), GrenadeAi.escape_runner(from, speed),
	])
	if fast["spot"] != Vector2.INF:
		_compare_tight(ctx, tally, fast, { "kind": kind, "burst": burst, "from": from,
				"speed": speed })
	_compare_existence(ctx, tally, {
		"kind": kind, "burst": burst, "from": from, "fuse": fuse, "speed": speed,
	})


## The same escape with the run allowed cut to the winner's own route (`fast["route"]` and a hair
## over): the winning spot then sits at the edge of what the search may reach (`work["bound"]`: the
## run allowed plus the start's slack, `EscapeSearch`), the one case where the straight line to it
## is nearly the bound, and the resolver's cut on that bound must keep it. A search that cut a
## candidate a little too soon (more than the slack's 2 px: a route that runs straight is within it)
## would pass the winner over, and the answer would differ from the plain search's.
func _compare_tight(ctx: Dictionary, tally: Dictionary, fast: Dictionary, c: Dictionary) -> void:
	var geometry = ctx["geometry"]
	var kind: StringName = c["kind"]
	var from: Vector2 = c["from"]
	var speed: float = c["speed"]
	var fuse: float = float(fast["route"]) / speed + AgentThrow.ARRIVE_MARGIN + 0.0001
	var radius: float = geometry.radius_of(kind)
	var threat := GrenadeAi.escape_threat(kind, radius, c["burst"], fuse)
	var runner := GrenadeAi.escape_runner(from, speed)
	var tight: Dictionary = geometry.escape(
		ctx["space"], ctx["map"], threat, runner, ctx["exclude"]
	)
	var plain := GrenadeAi.plain_escape(
		geometry,
		{ "space": ctx["space"], "map": ctx["map"], "exclude": ctx["exclude"] },
		threat,
		runner,
	)
	tally["tight"] += 1
	if (fast["spot"] as Vector2).distance_to(from) >= float(fast["route"]) - 0.5:
		tally["tight_straight"] += 1
	if tight != plain or tight["spot"] != fast["spot"]:
		tally["differing"].append("tight %s from %s: %s, plain %s, wide %s"
				% [kind, from.round(), tight, plain, fast])


## The sliced search (a few units a step, as the pool serves it) of the same question `asked`
## (`[threat, runner]`) lands on `whole`'s answer.
func _compare_sliced(ctx: Dictionary, tally: Dictionary, whole: Dictionary, asked: Array) -> void:
	var sliced: EscapeSearch = ctx["geometry"].begin_escape(
		ctx["space"], ctx["map"], asked[0], asked[1], ctx["exclude"]
	)
	while not sliced.done:
		sliced.step(3)
		tally["steps"] += 1
	if sliced.best != whole:
		tally["differing"].append("sliced %s from %s: %s, whole %s"
				% [asked[0].kind, asked[1].from.round(), sliced.best, whole])


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
