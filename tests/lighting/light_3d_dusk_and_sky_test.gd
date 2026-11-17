extends GameTest
## #193 phase 3 (L1 in 3D): the 3D render is lit at dusk. The toon shaders' ambient is the dusk's
## `ambient_color`; one `DirectionalLight3D`, the sky, is in `sky_color` and `sky_energy`, comes
## from the south-west (it travels toward +x and -y of the 2D world) high enough that a wall's
## shadow is short, and casts hard shadows; and it reaches only the street's floors, none of a
## tower's rooms (a tower is lit from within, as in 2D).
##
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D.sun()` and Art's `ToonLight`
## (`ambient()`, `sky_reaches(point)`).

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const Lights2D := preload("res://tests/_lighting/lighting_probe.gd")
const AMBIENT := Color(0.40, 0.37, 0.55)
const SKY := Color(1.0, 0.5, 0.42)


func describe() -> Dictionary:
	return {
		"name": "The 3D dusk: the ambient, a low-cost sky from the south-west on the street only",
		"description": "The toon ambient is the dusk's, the sky light is in its colour from the "
			+ "south-west with hard shadows and a short wall shadow, and it reaches the street's "
			+ "floors and none of the towers' rooms.",
		"tags": ["lighting", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.district(4)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var rooms := WorldGen.district_rooms(t.world.district)
	var lighting := Probe.light(t, rooms)
	if lighting == null:
		return
	t.check(
		ToonLight.ambient().is_equal_approx(AMBIENT),
		"the ambient is the dusk's (%s)" % ToonLight.ambient(),
	)
	var sun := lighting.sun()
	t.check(sun != null and sun.light_color.is_equal_approx(SKY), "the sky is in the dusk's colour")
	t.expect_near(sun.light_energy, 0.42, 0.001, "the sky is at its energy")
	t.check(sun.shadow_enabled, "the sky casts shadows")
	var travel := -sun.global_basis.z
	t.check(
		travel.x > 0.0 and travel.z < 0.0,
		"the sky travels toward +x and -y: it comes from the south-west (%s)" % travel,
	)
	var elevation := rad_to_deg(asin(-travel.y))
	t.expect_near(elevation, Lighting3DConfig.sun_elevation, 0.5, "the sky stands at its elevation")
	var shadow := ObjectStructureMeshConfig.wall_height / tan(deg_to_rad(elevation))
	t.check(shadow <= 30.0, "a wall's shadow is short (%.0f px)" % shadow)
	_check_reach(t, rooms)
	for room: Dictionary in rooms:
		t.check(
			not ToonLight.sky_reaches((room["rect"] as Rect2).get_center()),
			"the sky does not reach the room %s" % room["key"],
		)
		t.expect_eq(
			ToonLight.room_at((room["rect"] as Rect2).get_center()),
			rooms.find(room) + 1,
			"the room map has the room %s" % room["key"],
		)
	_check_globals_outlive(t, rooms)


## The sky reaches a street floor's ground exactly where no tower's room (or its walls) is.
func _check_reach(t: TestContext, rooms: Array) -> void:
	var reached := 0
	var wrong := 0
	for ground in Lights2D.floors(t.world.district):
		if not ground.is_street():
			continue
		var rect := Lights2D.floor_rect(ground)
		for x in range(int(rect.position.x) + 3, int(rect.end.x), 60):
			for y in range(int(rect.position.y) + 3, int(rect.end.y), 60):
				var open := not _in_tower(rooms, Vector2(x, y))
				wrong += 1 if ToonLight.sky_reaches(Vector2(x, y)) != open else 0
				reached += 1 if open else 0
	t.check(reached > 0, "the sky reaches street ground (%d points)" % reached)
	t.expect_eq(
		wrong,
		0,
		"the sky reaches a street floor's ground exactly where no tower's room (or its walls) is",
	)


## Whether `at` lies in a room of `rooms` or the walls round it.
func _in_tower(rooms: Array, at: Vector2) -> bool:
	return rooms.any(
		func(r: Dictionary) -> bool:
			return (r["rect"] as Rect2).grow(LightingConfig.floor_reach).has_point(at)
	)


## The globals belong to the last lighting standing: one built later and freed first leaves the
## first's, and when the last is freed they are the default (a grey ambient, no masks).
func _check_globals_outlive(t: TestContext, rooms: Array) -> void:
	var second := Probe.light(t, rooms)
	second.get_parent().remove_child(second)
	second.free()
	t.check(
		ToonLight.ambient().is_equal_approx(AMBIENT),
		"a second lighting freed leaves the first's ambient (%s)" % ToonLight.ambient(),
	)
	t.check(ToonLight.sky_rect().has_area(), "and its sky mask")
	for light in t.world.get_tree().get_nodes_in_group(&"world_lighting_3d"):
		light.get_parent().remove_child(light)
		light.free()
	t.check(
		ToonLight.ambient().is_equal_approx(ToonLightConfig.default_ambient),
		"with the last freed the ambient is the default (%s)" % ToonLight.ambient(),
	)
	t.check(not ToonLight.sky_rect().has_area(), "and the sky mask is cleared")
