extends GameTest
## D21 unbake (#194 17g, interface 20, `docs/lighting.md`): the desk's light is the monitor
## item's, not the desk's. The desk gives none; the monitor on it gives one at its screen; a
## monitor knocked off the desk takes its glow with it, to where it lands.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const AT := Vector2(400, 250)
## How far (px) the light may stand from its monitor: the screen's front, a step out.
const NEAR := 16.0


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
	var start := monitor.global_position
	Knockback.push(monitor, Vector2(0.0, 1200.0), Vector2.ZERO, 20.0)
	await t.seconds(1.5)
	var moved := monitor.global_position.distance_to(start)
	t.check(moved > 20.0, "the monitor was knocked off its place (%.0f px)" % moved)
	_check_at(t, own[0], monitor, "where it landed")


## `light` stands within `NEAR` px of `monitor`, and its own piece is still the monitor.
func _check_at(t: TestContext, light: OmniLight3D, monitor: Node2D, when: String) -> void:
	var off := Probe.ground_of(light).distance_to(monitor.global_position)
	t.check(off <= NEAR, "the monitor's light is at its screen %s (%.1f px)" % [when, off])
