extends GameTest
## #193 phase 3, L3 in 3D: a room's ceiling fixture is its light and its bulb. Every fixture has a
## bulb over its room's centre, above the walls' tops, glowing the fixture's colour lightened (an
## emissive part, so a lamp's colour is what shows whatever the light) and casting no shadow of
## its own; the fixture's light casts a shadow that lets some light through
## (`Lighting3DConfig.fixture_shadow_opacity`), so the floor under a table is the pool a step
## down and not the cold ambient alone.
##
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `fixtures()`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A ceiling fixture is a glowing bulb and a softly shadowed light",
		"description": "Each fixture has an emissive bulb over its room's centre above the "
			+ "walls, casting no shadow; its light's shadow is part dark only.",
		"tags": ["lighting", "3d"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var lighting := Probe.light(t, t.rooms)
	if lighting == null:
		return
	var fixtures := lighting.fixtures()
	if not t.require(not fixtures.is_empty(), "the house has room fixtures"):
		return
	var bulbs := lighting.get_children().filter(
		func(n: Node) -> bool: return n.name.begins_with("Bulb")
	)
	t.expect_eq(bulbs.size(), fixtures.size(), "every fixture has a bulb")
	for f: Dictionary in fixtures:
		var light: OmniLight3D = f["light"]
		t.check(
			light.shadow_opacity < 1.0 and light.shadow_opacity > 0.0,
			"%s's shadow is part dark (%.2f)" % [light.name, light.shadow_opacity],
		)
		var bulb := _bulb_over(bulbs, light)
		if not t.require(bulb != null, "%s has its bulb over it" % light.name):
			continue
		t.check(
			bulb.position.y >= LightingFixtureConfig.bulb_height * RenderConfig.unit - 0.01
				and LightingFixtureConfig.bulb_height > 96.0,
			"the bulb hangs over the walls' tops",
		)
		t.check(
			bulb.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"the bulb casts no shadow",
		)
		var glow: Color = bulb.get_instance_shader_parameter(&"emissive")
		t.check(glow.a > 0.5, "the bulb glows (%s)" % str(glow))
		t.check(glow.r > 0.9 and glow.r >= glow.b, "in the fixture's warm colour, lightened")


## The bulb standing over `light`'s ground point.
func _bulb_over(bulbs: Array, light: OmniLight3D) -> MeshInstance3D:
	var at := Probe.ground_of(light)
	for b: MeshInstance3D in bulbs:
		if Vector2(b.position.x, b.position.z).distance_to(at * RenderConfig.unit) < 0.01:
			return b
	return null
