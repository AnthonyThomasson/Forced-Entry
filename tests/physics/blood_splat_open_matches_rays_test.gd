extends GameTest
## A splat in open space can skip its per-feature wall-clipping rays only when one conservative
## broadphase proves that no blocking collider reaches any possible part of it. Seeded splats in
## the open, beside the arena walls and around furniture must keep the exact ray-built outlines and
## consume the same random draws; the skip counter proves the open-space path was exercised.

const BloodSplat = preload("res://scenes/physics/blood/blood_splat.gd")
const SPLATS := 160
const SEED := 192_014
## Where the edge cases put the splat: far from the arena walls and the furniture.
const EDGE_AT := Vector2(130, 200)


func describe() -> Dictionary:
	return {
		"name": "Open-space splats match the per-feature ray build",
		"description": "The splat broadphase changes neither outlines nor RNG draws in the open "
			+ "or beside walls and furniture, and skips rays only when the whole splat is clear.",
		"tags": ["blood", "splat", "broadphase"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(320, 190))
	s.object(&"sofa", "sofa", Vector2(440, 260))


func run(t: TestContext) -> void:
	await t.frames(2)
	var differing: Array[int] = []
	var built := 0
	var rays := [0, 0]  # exact-ray callbacks: open space, near geometry
	for i in SPLATS:
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED + i
		var at := _position(i, rng)
		var throw := BloodThrow.new()
		throw.size = rng.randf_range(1.0, 7.0)
		throw.direction = (Vector2.from_angle(rng.randf() * TAU)
				if rng.randf() < 0.8
				else Vector2.ZERO)
		throw.energy = rng.randf()
		seed(SEED + i)
		var fast := _splat(t, RayDispatchSplat, at, throw)
		rays[0 if i % 4 == 0 else 1] += fast.exact_rays
		var fast_draw := randf()
		seed(SEED + i)
		var plain := _splat(t, EveryRaySplat, at, throw)
		var plain_draw := randf()
		built += fast.shapes.size()
		if fast.shapes != plain.shapes or fast_draw != plain_draw:
			differing.append(i)
		fast.free()
		plain.free()
	t.check(built >= SPLATS, "the seeded splats built outlines (%d)" % built)
	t.check(differing.is_empty(), "splats differing from the exact rays: %s" % str(differing))
	t.check(rays[0] == 0, "open-space splats skipped every exact clipping ray")
	t.check(rays[1] > 0, "splats near geometry kept the exact clipping rays")
	for radius in [3.0, 7.0]:
		await _bound_edge(t, radius)


## A wall just beyond the splat's published clear radius leaves it clear (no ray is cast, the
## outlines are the plain build's); the same wall just inside the radius keeps the exact rays. The
## radius itself must cover the farthest a clipping ray goes, worked out here from the generator's
## own extremes: a spike's tip (base 0.7 core radii widened by the stretch, plus up to 1.6 lengths
## lengthened by 0.9 of the energy) and a satellite (reach 3.4 lengthened by 0.8 of the energy).
func _bound_edge(t: TestContext, radius: float) -> void:
	var bound := BloodSplat.clear_radius(radius)
	var tip := 0.7 * (1.0 + BloodSplatConfig.stretch) + BloodSplatConfig.spike_length_max * 1.9
	var farthest := radius * maxf(tip, BloodSplatConfig.satellite_reach_max * 1.8)
	t.check(bound >= farthest, "radius %.0f: the clear radius covers the farthest ray" % radius)
	t.check(bound <= farthest * 1.25 + 2.0, "radius %.0f: and is not wastefully wide" % radius)
	for outside in [true, false]:
		var wall := StaticBody2D.new()
		wall.collision_layer = PhysicsConfig.wall_mask
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = Vector2(20, 300)
		wall.add_child(shape)
		wall.position = EDGE_AT + Vector2(bound + (1.0 if outside else -1.0) + 10.0, 0.0)
		t.world.add_child(wall)
		await t.frames(2)
		var made := _beside_wall(t, radius)
		var label := "radius %.0f, wall just %s the clear radius" % [
			radius, "outside" if outside else "inside"]
		t.check(made["differing"].is_empty(), "%s: splats differing from the exact rays %s" % [
			label, str(made["differing"])])
		if outside:
			t.check(made["rays"] == 0, "%s: no ray was cast" % label)
		else:
			t.check(made["rays"] > 0, "%s: the exact rays were kept" % label)
		wall.free()
		await t.frames(1)


## Twelve seeded splats of core radius `radius`, each against the plain build: the exact rays the
## fast build cast, and which of them came out differently.
func _beside_wall(t: TestContext, radius: float) -> Dictionary:
	var rays := 0
	var differing: Array[int] = []
	for i in 12:
		var throw := BloodThrow.new()
		throw.size = radius
		throw.energy = 1.0 if i % 2 == 0 else 0.4
		throw.direction = Vector2.RIGHT if i % 3 != 0 else Vector2.from_angle(i * 0.5)
		seed(SEED + i)
		var fast := _splat(t, RayDispatchSplat, EDGE_AT, throw)
		var fast_draw := randf()
		seed(SEED + i)
		var plain := _splat(t, EveryRaySplat, EDGE_AT, throw)
		if fast.shapes != plain.shapes or fast_draw != randf():
			differing.append(i)
		rays += fast.exact_rays
		fast.free()
		plain.free()
	return { "rays": rays, "differing": differing }


func _position(i: int, rng: RandomNumberGenerator) -> Vector2:
	match i % 4:
		0:
			return Vector2(rng.randf_range(70.0, 240.0), rng.randf_range(60.0, 340.0))
		1:
			if i % 8 == 1:
				return Vector2(rng.randf_range(5.0, 24.0), rng.randf_range(40.0, 360.0))
			return Vector2(rng.randf_range(40.0, 560.0), rng.randf_range(5.0, 24.0))
		2:
			return Vector2(320, 190) + Vector2(
				rng.randf_range(-65.0, 65.0), rng.randf_range(-65.0, 65.0),
			)
		_:
			return Vector2(440, 260) + Vector2(
				rng.randf_range(-90.0, 90.0), rng.randf_range(-70.0, 70.0),
			)


func _splat(t: TestContext, script: Script, at: Vector2, throw: BloodThrow) -> Node:
	var node := Node2D.new()
	node.script = script
	t.world.add_child(node)
	node.global_position = at
	node.call(&"setup", throw.size, throw.direction, throw.energy, throw.exclude)
	return node


## The observed build: exact rays go through this callback, so the test can tell an open-space
## skip from the near-geometry path. Its body is the original clipping ray, independently held here.
class RayDispatchSplat extends "res://scenes/physics/blood/blood_splat.gd":
	var exact_rays := 0

	func _ray_fraction(p: Vector2) -> float:
		exact_rays += 1
		var local := _at(p)
		if local.length_squared() < 0.0001:
			return 1.0
		var ray := PhysicsRayQueryParameters2D.create(
			global_position, global_position + local, PhysicsConfig.wall_mask,
		)
		ray.exclude = _exclude
		var hit := _space.intersect_ray(ray)
		if hit.is_empty():
			return 1.0
		return (hit.position as Vector2).distance_to(global_position) / local.length()


## The reference build: never take the broadphase, so every feature keeps its exact clipping ray.
class EveryRaySplat extends "res://scenes/physics/blood/blood_splat.gd":
	func _fully_clear() -> bool:
		return false
