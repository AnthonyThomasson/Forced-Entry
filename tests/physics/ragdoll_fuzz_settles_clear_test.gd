extends GameTest
## D12 (#194): fallen bodies come to rest clear of the solids, whatever hit them. Thirty-odd dead
## men are blown at a desk, a sofa, a fridge, a corner and a wall from random sides and heights
## (seeded); the moment each body sleeps, no joint's sphere overlaps a body of the twin space, and
## no more than a few took the full `max_time` to settle (a leg propped on its knee may creep until
## its time runs out).

const CharacterScene := preload("res://scenes/character/character_base.tscn")
const CharacterRagdoll := preload("res://scenes/character/body/character_ragdoll.gd")
const SEED := 20_260_512
## Where the blows are driven: the object's id and kind, its place and how far its far side is.
const TARGETS := [
	[&"desk", "desk", Vector2(300, 120), 62.0],
	[&"sofa", "sofa", Vector2(600, 260), 45.0],
	[&"fridge", "fridge", Vector2(400, 450), 36.0],
]
## Bodies blown at each target, and in the corner and at the wall.
const AROUND := 8
const IN_CORNER := 4
const AT_WALL := 4
## How much (px) smaller than the joint's own sphere the probe is: a joint pressed against a face
## may sink a fraction of a pixel into it (the solver's sweeps are stepwise), never a pixel.
const PROBE_LESS := 1.0
## The fall's length in frames (`PhysicsRagdollConfig.max_time` 5 s, at 60 a second, and some).
const FRAMES := 330
## The most bodies that may run out their time instead of coming to rest.
const MOST_LATE := 4

var _bodies: Array = []


func describe() -> Dictionary:
	return {
		"name": "Fallen bodies rest clear of the solids",
		"description": "Seeded dead men blown at a desk, a sofa, a fridge, a corner and a wall: "
			+ "as each sleeps no joint overlaps a wall or a piece, and most settle before the "
			+ "fall's time is up.",
		"tags": ["ragdoll", "death", "3d", "fuzz", "furniture", "wall"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.switch(&"audio.sound", false)
	for target in TARGETS:
		s.object(target[0], target[1], target[2])


func run(t: TestContext) -> void:
	await t.frames(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for target in TARGETS:
		for k in AROUND:
			var around: Vector2 = target[2]
			var angle := TAU * (float(k) + rng.randf_range(-0.2, 0.2)) / float(AROUND)
			_add(t, around + Vector2.from_angle(angle) * (float(target[3]) + 30.0), around)
	for k in IN_CORNER:
		_add(t, Vector2(26, 26) + Vector2(k * 3.0, k * 5.0), Vector2.ZERO)
	for k in AT_WALL:
		_add(t, Vector2(24, 400 + k * 40.0), Vector2(0, 400 + k * 40.0))
	await t.frames(2)
	for body in _bodies:
		_shoot(body, rng)
	var rested := {}
	var overlapping := 0
	for frame in FRAMES:
		await t.frames(1)
		for k in _bodies.size():
			var ragdoll: CharacterRagdoll = _bodies[k]["ragdoll"]
			if not rested.has(k) and ragdoll.is_settled():
				rested[k] = frame
				if _overlaps(t, _bodies[k]):
					overlapping += 1
	var late := 0
	var timeout := ceili(PhysicsRagdollConfig.max_time * 60.0) - 2
	for k in _bodies.size():
		late += 1 if int(rested.get(k, FRAMES)) >= timeout else 0
	print("ragdoll fuzz: %d of %d bodies ran out their time" % [late, _bodies.size()])
	t.expect_eq(rested.size(), _bodies.size(), "every body comes to rest")
	t.expect_eq(overlapping, 0, "no body sleeps with a joint inside a wall or a piece")
	t.check(
		late <= MOST_LATE,
		"at most %d of %d bodies run out their time (%d did)" % [MOST_LATE, _bodies.size(), late],
	)


## A man at `at` (a dictionary of his node and ragdoll, to fill when shot) to be blown toward `aim`.
func _add(t: TestContext, at: Vector2, aim: Vector2) -> void:
	var character := CharacterScene.instantiate()
	character.start_slot = ItemRegistry.UNARMED_SLOT
	t.world.add_child(character)
	character.global_position = at.clamp(Vector2(20, 20), Vector2(880, 580))
	_bodies.append({ "node": character, "at": character.global_position, "aim": aim })


## Kill the man with a blow toward his aim, turned a little at random, at a random height.
func _shoot(body: Dictionary, rng: RandomNumberGenerator) -> void:
	var character: Node = body["node"]
	var toward := ((body["aim"] as Vector2) - (body["at"] as Vector2)).normalized()
	if toward.length() < 0.5:
		toward = Vector2(-1.0, -1.0).normalized()
	var blow := toward.rotated(rng.randf_range(-0.6, 0.6))
	var hit := HitInfo.new()
	hit.position = body["at"]
	hit.normal = -blow
	hit.direction = blow
	hit.damage = 1000.0
	hit.height = rng.randf_range(20.0, 60.0)
	character.take_hit(hit)
	body["ragdoll"] = character.anatomy.ragdoll


## Whether any joint's sphere of the body, as it lies, overlaps a body of the twin space.
func _overlaps(t: TestContext, body: Dictionary) -> bool:
	var ragdoll: CharacterRagdoll = body["ragdoll"]
	var space := TwinSpace.space_of(t.world)
	var sphere := SphereShape3D.new()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = PhysicsConfig.twin_mask
	for i in ragdoll.body.point_count():
		var p := ragdoll.point(i)
		var radius: float = ragdoll.body._radius[i]
		sphere.radius = (radius - PROBE_LESS) * RenderConfig.unit
		var height := maxf(p.z * ragdoll.body.height_scale, radius + SmallFlight.GROUND_GAP)
		var plan := (body["node"] as Node2D).global_position + Vector2(p.x, p.y)
		query.transform = Transform3D(Basis(), PlanSpace.lift(plan, height))
		if not space.intersect_shape(query, 1).is_empty():
			return true
	return false
