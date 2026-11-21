extends GameTest
## D21 unbake (#194 17g, interface 20, `docs/lighting.md`): the desk's light is the monitor
## item's, not the desk's. The desk gives none; the monitor on it gives one at its screen; a
## monitor knocked off the desk takes its glow with it, to where it lands.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const AT := Vector2(400, 250)
## How far (px) the light may stand from its monitor: its pool's centre, `ahead` (22) past the
## screen's front edge and half the item's depth (4) from its middle, and a little over.
const NEAR := 30.0


func describe() -> Dictionary:
	return {
		"name": "A monitor knocked off its desk takes its glow",
		"description": "The desk gives no light; the monitor item on it gives one; shoved off "
			+ "the desk it lands elsewhere with its light still at its screen.",
		"tags": ["lighting", "3d", "items", "unbake"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"desk", "desk", AT, { "neon": "" })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var desk: Node2D = t.object(&"desk")
	var carried := RoomItems.carry(desk, ObjectDefinitions.get_definition("desk"), t.world)
	var monitor: Node2D = null
	for c: Dictionary in carried:
		if c["key"] == "monitor":
			monitor = c["node"]
	if not t.require(monitor != null, "the desk carries a monitor"):
		return
	await t.seconds(2.0)
	var lighting := Probe.light(t)
	if lighting == null:
		return
	t.check(Probe.lights_of(lighting, desk).is_empty(), "the desk gives no light of its own")
	var own := Probe.lights_of(lighting, monitor)
	if not t.require(own.size() == 1, "the monitor gives one light (%d)" % own.size()):
		return
	_check_at(t, own[0], monitor, "on the desk")
	var up := _height_of(own[0])
	var top := PieceHeights.top_of_spec(FurnitureSpec.of(desk))
	t.check(up > top, "on the desk the light hangs over its top (%.1f over %.1f)" % [up, top])
	var start := monitor.global_position
	Knockback.push(monitor, Vector2(0.0, 2000.0), Vector2.ZERO, 20.0)
	await t.seconds(1.5)
	var moved := monitor.global_position.distance_to(start)
	t.check(moved > 2.0 * NEAR, "the monitor was knocked well off its place (%.0f px)" % moved)
	_check_at(t, own[0], monitor, "where it landed")
	var down := _height_of(own[0])
	t.check(
		down < ObjectMeshItemConfig.monitor_height,
		"on the floor the light hangs within the monitor's own height (%.1f px)" % down,
	)
	t.check(down < up - 10.0, "the glow came down with it (%.1f px, %.1f on the desk)" % [down, up])


## `light` stands within `NEAR` px of `monitor`, and its own piece is still the monitor.
func _check_at(t: TestContext, light: OmniLight3D, monitor: Node2D, when: String) -> void:
	var off := Probe.ground_of(light).distance_to(monitor.global_position)
	t.check(off <= NEAR, "the monitor's light is at its screen %s (%.1f px)" % [when, off])
	var twin := TwinSpace.twin_for(monitor)
	if t.require(twin != null, "the monitor has a twin %s" % when):
		var lift := float(ObjectArtLightConfig.specs["monitor"]["lift"])
		t.expect_near(
			_height_of(light), twin.global_position.y / RenderConfig.unit + lift, 1.0,
			"the light hangs its lift over the monitor's base %s" % when,
		)
		t.expect_near(
			Probe.floor_reach(light), 105.0 * Lighting3DConfig.range_scale, 0.5,
			"its pool still reaches its radius on the floor %s" % when,
		)


## How high (px) `light` hangs over the floor.
func _height_of(light: OmniLight3D) -> float:
	return light.position.y / RenderConfig.unit
