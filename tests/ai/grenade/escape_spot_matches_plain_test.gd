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
	var tally := { "compared": 0, "found": 0, "differing": [] }
	for n in CASES:
		var room: Dictionary = rooms[n % rooms.size()]
		_compare_case(ctx, tally, room["rect"])
	var compared: int = tally["compared"]
	var found: int = tally["found"]
	var differing: Array = tally["differing"]
	t.check(
		compared == CASES * 2 and found >= CASES / 2.0,
		"escapes compared (%d, %d with a spot)" % [compared, found],
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
		space, map, _threat(kind, radius, burst, fuse), _runner(from, speed), exclude,
	)
	var plain := GrenadeAi.plain_escape(
		geometry,
		{ "space": space, "map": map, "exclude": exclude },
		_threat(kind, radius, burst, fuse),
		_runner(from, speed),
	)
	tally["compared"] += 1
	tally["found"] += 1 if fast["spot"] != Vector2.INF else 0
	if fast != plain:
		tally["differing"].append("%s at %s from %s: %s, plain %s"
				% [kind, burst.round(), from.round(), fast, plain])


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
