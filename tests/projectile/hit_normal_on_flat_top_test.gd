extends GameTest
## A round that comes down on the flat top of an object (a table's top, a low box) hands it a hit
## whose `normal` is still a unit vector on the floor plan (interface 3: receivers dent, spray and
## shove along it): the top's own normal has no floor part, so the hit's normal is back along the
## round's plan heading, toward the shooter.

const TOP := 30.0


func describe() -> Dictionary:
	return {
		"name": "A round striking a flat top hits along a unit normal",
		"description": "A round falling steeply onto a low box's top: the hit's normal has unit "
			+ "length and points back along the round's heading.",
		"tags": ["projectile", "normal", "ballistics"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)


func run(t: TestContext) -> void:
	var twins: TwinSpace = t.world.twin_space()
	twins.builders.append(_twin_of_box)
	var box := Box.new()
	box.position = Vector2(400, 250)
	t.world.add_child(box)
	await t.frames(3)
	t.require(twins.twin_of(box) != null, "premise: the box has a twin")
	var shot := Shot.new()
	shot.rise = -1.0
	ProjectileSpawner.spawn(Vector2(350, 250), Vector2.RIGHT, t.world, shot)
	await t.seconds(0.6)
	if not t.require(not box.hits.is_empty(), "the round struck the box"):
		return
	var hit: HitInfo = box.hits[0]
	t.expect_near(hit.height, TOP, 0.6, "on its top (%.1f px)" % hit.height)
	t.expect_near(hit.normal.length(), 1.0, 0.01, "the normal is a unit vector (%s)" % hit.normal)
	t.expect_near(hit.normal.dot(Vector2.LEFT), 1.0, 0.01, "back along the round's heading")


## The box's twin: 80 px square on the floor, `TOP` high.
func _twin_of_box(node: Node2D) -> Node3D:
	if not node is Box:
		return null
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.TWIN_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, TOP, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, TOP * 0.5, 0.0)
	body.add_child(shape)
	return body


## A body that says what it is and keeps the hits it takes.
class Box extends StaticBody2D:
	var hits: Array[HitInfo] = []

	func get_surface() -> Dictionary:
		return { "penetration": 5.0, "material": "wood", "color": Color.WHITE }

	func take_hit(info: HitInfo) -> void:
		hits.append(info)
