extends GameTest
## A round that skims down onto the hard flat top of an object ricochets in 3D: reflected off the
## top's normal (straight up), it leaves climbing, with the same floor-plan heading, and the hit
## says ricochet (interface 3). A steep one is not a glance and goes through the same top.

const TOP := 30.0
const BOX_X := 400.0


func describe() -> Dictionary:
	return {
		"name": "A shallow round ricochets off a hard top and climbs",
		"description": "A round falling gently onto a metal slab's top is reflected upward; "
			+ "a steep one is not a glance.",
		"tags": ["projectile", "ricochet", "ballistics"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)


func run(t: TestContext) -> void:
	var twins: TwinSpace = t.world.twin_space()
	twins.builders.append(_twin_of_slab)
	var slab := Slab.new()
	slab.position = Vector2(BOX_X, 250)
	t.world.add_child(slab)
	await t.frames(3)
	t.require(twins.twin_of(slab) != null, "premise: the slab has a twin")

	var skimming := Shot.new()
	skimming.height = TOP + 3.0
	skimming.rise = -0.1
	var round_ := ProjectileSpawner.spawn(
		Vector2(BOX_X - 45.0, 250),
		Vector2.RIGHT,
		t.world,
		skimming,
	)
	await t.frames(4)
	t.require(not slab.hits.is_empty(), "the skimming round struck the slab")
	var hit: HitInfo = slab.hits[0]
	t.expect_near(hit.height, TOP, 0.6, "on its top (%.1f px)" % hit.height)
	t.check(is_instance_valid(round_), "and flew on")
	if is_instance_valid(round_):
		t.check(round_.rise > 0.0, "climbing after the bounce (rise %.3f)" % round_.rise)
		t.check(round_.direction.x > 0.99, "on its heading in plan (%s)" % round_.direction)
	t.check(
		t.happened(&"hit", func(d): return d["victim"] == slab and d["outcome"] == &"ricochet"),
		"the hit is a ricochet",
	)

	var steep := Shot.new()
	steep.height = 70.0
	steep.rise = -1.0
	ProjectileSpawner.spawn(Vector2(BOX_X - 40.0, 250), Vector2.RIGHT, t.world, steep)
	await t.seconds(0.5)
	t.check(
		t.happened(&"hit", func(d): return d["victim"] == slab and d["outcome"] != &"ricochet"),
		"a steep round is no glance: it does not ricochet",
	)


## The slab's twin: 80 px square on the floor, `TOP` high.
func _twin_of_slab(node: Node2D) -> Node3D:
	if not node is Slab:
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
class Slab extends StaticBody2D:
	var hits: Array[HitInfo] = []

	func get_surface() -> Dictionary:
		return { "coverage": 100.0, "penetration": 90.0, "material": "metal", "color": Color.WHITE }

	func take_hit(info: HitInfo) -> void:
		hits.append(info)
