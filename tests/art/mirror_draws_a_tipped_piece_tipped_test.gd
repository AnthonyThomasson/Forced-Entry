extends GameTest
## The 3D render mirror follows a free piece's 3D body (#194 furn3d): a bookshelf knocked over is
## drawn lying on its side, its mesh turned with the body, not stood upright where its 2D footprint
## is (`MeshCarrier`, interface 27).

const Probe := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(300, 200)


func describe() -> Dictionary:
	return {
		"name": "A tipped bookshelf is drawn tipped",
		"description": "The bookshelf's mesh stands upright; knocked over, its mesh lies on its "
			+ "side (its up axis leans past 60 degrees) with the 3D body, and is at rest asleep.",
		"tags": ["mirror", "render3d", "furniture", "tipping", "3d"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.object(&"shelf", "bookshelf", AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	ObjectMeshes.register(mirror.builders)
	view.add_child(mirror)
	mirror.carry(t.world)
	await t.frames(5)
	var shelf := t.object(&"shelf")
	var proxies: Array = mirror.proxies_of(shelf)
	if not t.require(not proxies.is_empty(), "premise: the bookshelf is mirrored"):
		return
	var mesh := proxies[0] as Node3D
	t.check(absf(mesh.global_transform.basis.y.y) > 0.99, "standing, its mesh stands upright")
	Knockback.push(shelf, Vector2(9000.0, 0.0), Vector2.ZERO, Probe.top(shelf) - 4.0)
	await t.seconds(0.2)
	await Probe.settle(t, shelf, 10.0)
	await t.frames(3)
	t.require(Probe.lean(shelf) > 60.0, "premise: it lies over (%.0f degrees)" % Probe.lean(shelf))
	mesh = mirror.proxies_of(shelf)[0] as Node3D
	var lean := rad_to_deg(acos(clampf(mesh.global_transform.basis.y.y, -1.0, 1.0)))
	t.check(lean > 60.0, "its mesh lies on its side too (%.0f degrees)" % lean)
	var body := Probe.body(shelf)
	t.check(
		mesh.global_position.distance_to(body.global_position) < 0.5,
		"at the 3D body's place (%s, the body at %s)" % [
			mesh.global_position,
			body.global_position,
		],
	)
