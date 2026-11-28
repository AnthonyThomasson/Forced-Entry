extends GameTest
## V6 (#194, D13): a vehicle and a piece of furniture share one 3D space, and one pull
## toward the floor. The Vehicles domain may not read Objects, so its gravity is its own number
## (`VehicleCollisionConfig.gravity`); this pins it to `PieceBodyConfig.gravity`, and to the pull
## each body really has in its world.


func describe() -> Dictionary:
	return {
		"name": "A vehicle falls as furniture does",
		"description": "VehicleCollisionConfig.gravity equals PieceBodyConfig.gravity, and a "
			+ "vehicle's 3D body carries that gravity.",
		"tags": ["vehicle", "furniture", "3d", "config"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(300, 300))
	s.object(&"shelf", "bookshelf", Vector2(600, 300))


func run(t: TestContext) -> void:
	await t.frames(4)
	t.check(
		is_equal_approx(VehicleCollisionConfig.gravity, PieceBodyConfig.gravity),
		"the two holders' gravity is one number (%.1f against %.1f px/s²)"
			% [VehicleCollisionConfig.gravity, PieceBodyConfig.gravity],
	)
	var car := TwinSpace.leader_of(t.vehicle(&"car"))
	var shelf := TwinSpace.leader_of(t.object(&"shelf"))
	if not t.require(car != null and shelf != null, "both bodies are 3D leaders"):
		return
	t.check(
		is_equal_approx(car.gravity_scale, shelf.gravity_scale),
		"and their bodies' gravity scales are (%.3f against %.3f)"
			% [car.gravity_scale, shelf.gravity_scale],
	)
