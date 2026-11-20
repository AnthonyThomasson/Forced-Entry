extends GameTest
## D5 (#194 vehicles3d): one source for a vehicle's heights, `VehicleMeshConfig.heights`: the garage
## prop car's mesh reads it, and the vehicle's 3D body is the real shape:
## the whole body to the belt, the cabin on to the roof over its own footprint (the glass and roof a
## grenade can rest on, a bullet can strike, a sight line is stopped by).

const TwinProbe := preload("res://tests/_general/twin_probe.gd")
const AT := Vector2(600, 400)
const KINDS := [&"car", &"van"]


func describe() -> Dictionary:
	return {
		"name": "A vehicle's heights come from one holder and its 3D body has a roof",
		"description": "The prop car and the mirror's stand-in take their heights from "
			+ "VehicleMeshConfig; dropped on, the vehicle's twin is as tall as the belt at the "
			+ "bonnet and as tall as the roof over the cabin.",
		"tags": ["vehicle", "3d", "heights", "twins"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1600, 1000), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", AT)
	s.vehicle(&"van", &"van", AT + Vector2(0, 400))


func run(t: TestContext) -> void:
	await t.frames(4)
	var car := VehicleMeshConfig.heights[&"car"] as Dictionary
	t.expect_near(ObjectMeshCarConfig.body_top(), car["belt"], 0.01, "the prop car's body top")
	t.expect_near(ObjectMeshCarConfig.roof_top(), car["roof"], 0.01, "the prop car's roof")
	for kind in KINDS:
		var row := VehicleMeshConfig.heights[kind] as Dictionary
		var looks: Dictionary = VehicleConfig.looks[kind]
		var node := t.vehicle(kind) as Node2D
		var roof: Vector2 = looks["roof"]
		var along := Vector2.RIGHT.rotated(node.global_rotation)
		var cabin := node.global_position + along * (roof.x + roof.y) * 0.5
		var bonnet := node.global_position + along * ((float(looks["bonnet"]) + 0.5 *
				(VehicleConfig.kinds[kind]["size"] as Vector2).x) * 0.5)
		t.expect_near(
			TwinProbe.top_at(t, cabin, PhysicsLayers.TWIN_VEHICLE),
			row["roof"],
			0.5,
			"a %s's twin over its cabin is as tall as its roof" % kind,
		)
		t.expect_near(
			TwinProbe.top_at(t, bonnet, PhysicsLayers.TWIN_VEHICLE),
			row["belt"],
			0.5,
			"and over its bonnet as tall as its belt",
		)
