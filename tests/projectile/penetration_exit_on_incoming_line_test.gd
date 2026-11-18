extends GameTest
## A round that penetrates an object has its exit found along the line it came in on (interface 3,
## `HitInfo.has_exit` / `exit_position`), however the penetration then turns it: the probe for the
## far face runs on the incoming line, not on the line the round leaves by. A stand-in body (a thin
## slab with a twin) records the hit's `HitInfo`; with a deflection of up to 40 degrees every round
## still has its exit on the slab's far face, on the line it came in on.

const SLAB_X := 400.0
const SLAB_THICK := 10.0
const ROUNDS := 12
const FROM_X := 150.0


func describe() -> Dictionary:
	return {
		"name": "A penetrating round's exit is found on its incoming line",
		"description": "Rounds through a slab with a strong deflection: each hit has an exit on "
			+ "the far face of the slab, where the incoming line meets it.",
		"tags": ["projectile", "penetration", "exit", "ballistics"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"penetrate_deflect_max_deg", 40.0)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0)


func run(t: TestContext) -> void:
	var twins: TwinSpace = t.world.twin_space()
	twins.builders.append(_twin_of_slab)
	var slab := Slab.new()
	slab.position = Vector2(SLAB_X, 250)
	t.world.add_child(slab)
	await t.frames(3)
	t.require(twins.twin_of(slab) != null, "premise: the slab has a twin")
	for i in ROUNDS:
		var shot := Shot.new()
		shot.penetration = 3.0
		ProjectileSpawner.spawn(
			Vector2(FROM_X, 250.0 - 90.0 + 15.0 * i),
			Vector2.RIGHT,
			t.world,
			shot,
		)
	await t.seconds(1.0)
	t.require(
		slab.hits.size() >= ROUNDS,
		"premise: every round struck the slab (%d)" % slab.hits.size(),
	)
	var through := slab.hits.filter(func(h: HitInfo) -> bool: return h.penetrated)
	t.require(
		through.size() * 2 >= ROUNDS,
		"premise: most rounds went through (%d)" % through.size(),
	)
	for hit: HitInfo in through:
		if not t.check(hit.has_exit, "a penetrating round has an exit (at %s)" % hit.position):
			continue
		t.expect_near(
			hit.exit_position.x, SLAB_X + SLAB_THICK * 0.5, 0.6,
			"on the far face of the slab (%.1f)" % hit.exit_position.x,
		)
		t.expect_near(
			hit.exit_position.y, hit.position.y, 0.6,
			"on the line the round came in on (%.1f against %.1f)"
				% [hit.exit_position.y, hit.position.y],
		)


## The slab's twin: a thin tall box, the 3D of the 2D body's centre.
func _twin_of_slab(node: Node2D) -> Node3D:
	if not node is Slab:
		return null
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.TWIN_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SLAB_THICK, 100.0, 180.0)
	shape.shape = box
	shape.position = Vector3(0.0, 50.0, 0.0)
	body.add_child(shape)
	return body


## A body that says what it is and keeps the hits it takes.
class Slab extends StaticBody2D:
	var hits: Array[HitInfo] = []

	func get_surface() -> Dictionary:
		return { "coverage": 100.0, "penetration": 60.0, "material": "wood", "color": Color.WHITE }

	func take_hit(info: HitInfo) -> void:
		hits.append(info)
