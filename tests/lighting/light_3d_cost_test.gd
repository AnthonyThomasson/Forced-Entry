extends GameTest
## #193 phase 3 (L4 in 3D): the 3D lights are cheap. Ten lamps and six neon tubes in one room (more
## than the floor's budget) are chosen by the view's focus: at most `LightingCostConfig.max_lights`
## are on and the ones far from the view are off; at most `shadow_lights` cast a shadow, none of
## them a low light (a tube); and with no focus every light stays on and none casts a shadow.
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `lights()`,
## `shadowed_count()`,
## `on_count()`, `choose()`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const ROOM := Rect2(0, 0, 4000, 600)
const LAMPS := 10
const TUBES := 6


func describe() -> Dictionary:
	return {
		"name": "The 3D lights are on near the view and only a few cast shadows",
		"description": "Many lamps and tubes along a long room: the lights near the view's focus "
			+ "are on, the far ones off, at most the shadow cap cast shadows and never a low "
			+ "light; "
			+ "without a focus all are on and none casts.",
		"tags": ["lighting", "3d"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ROOM)
	s.switch(&"nav.rebake", false)
	for i in LAMPS:
		s.object(
			StringName("lamp_%d" % i),
			"lamp",
			Vector2(150.0 + 380.0 * i, 150.0),
			{ "neon": "" },
		)
	for i in TUBES:
		s.object(StringName("tube_%d" % i), "neon_tube", Vector2(300.0 + 600.0 * i, 400.0))


func run(t: TestContext) -> void:
	var lighting := Probe.light(t)
	if lighting == null:
		return
	var kept := lighting.lights().size()
	t.check(kept > 0, "lights are placed (%d)" % kept)
	t.expect_eq(lighting.on_count(), kept, "with no focus every light is on")
	t.expect_eq(lighting.shadowed_count(), 0, "with no focus none casts a shadow")
	# Now a view at the left end of the room, 100 px across: it reaches only the lights near it.
	var focus := [Vector2(300.0, 300.0)]
	var lit := Probe.light(t, [], func() -> Vector2: return focus[0], 600.0)
	lit.choose()
	var near := lit.lights().filter(func(l: Node3D) -> bool: return l.visible)
	t.check(
		lit.on_count() == near.size() and near.size() <= LightingCostConfig.max_lights,
		"at most %d lights are on (%d)" % [LightingCostConfig.max_lights, near.size()],
	)
	t.check(
		lit.shadowed_count() <= LightingCostConfig.shadow_lights,
		"at most %d lights cast a shadow (%d)" % [
			LightingCostConfig.shadow_lights,
			lit.shadowed_count(),
		],
	)
	for l: OmniLight3D in lit.lights():
		if l.shadow_enabled:
			t.check(l.visible, "%s casts a shadow only while it is on" % l.name)
			t.check(
				l.position.y > Lighting3DConfig.low_height,
				"%s casting a shadow is an overhead light" % l.name,
			)
	# Moving the focus the length of the room turns the near lights off and the far ones on.
	var before := near.size()
	focus[0] = Vector2(3700.0, 300.0)
	lit.choose()
	var far_on := lit.lights().filter(
		func(l: Node3D) -> bool: return l.visible and Probe.ground_of(l).x > 3000.0
	)
	t.check(
		not far_on.is_empty() and before > 0,
		"moving the focus switches on the lights at the far end",
	)
	for l: OmniLight3D in lit.lights():
		if Probe.ground_of(l).x < 1000.0:
			t.check(
				not l.visible or Probe.floor_reach(l) > 2000.0,
				"%s is off, far from the view" % l.name,
			)
	_check_no_cap(t, lit)


## A cap of none switches the shadows off, and does not trip the choice.
func _check_no_cap(t: TestContext, lit: WorldLighting3D) -> void:
	var most := LightingCostConfig.shadow_lights
	LightingCostConfig.shadow_lights = 0
	lit.choose()
	LightingCostConfig.shadow_lights = most
	t.expect_eq(lit.shadowed_count(), 0, "with a cap of none no light casts a shadow")
