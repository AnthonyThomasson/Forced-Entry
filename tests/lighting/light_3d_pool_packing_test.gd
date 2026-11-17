extends GameTest
## #193 phase 3 (L2 in 3D, a pool is the same at any height): a light's `light_specular` carries
## what the toon light needs to give its pool its shape on the floor (its slope, its room and street
## flag, its height over the pool's rim and the height itself), whatever height it hangs at or casts
## its shadow from. A lamp, a street lamp's head, a screen and a room's ceiling fixture (cast from
## `Lighting3DConfig.fixture_height`) each read back, through the shader's own decode, their slope,
## room, street flag, the ratio of their height to their pool's rim (within a sixteenth) and their
## height (within one step of 1.4); and a flash the same at hand height.
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D.lights()`, `fixtures()`,
## `decode`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const SEED := 1
## How far the ratio may be from the truth (a sixteenth of a unit of ratio) and the height (one
## class of `ToonLight.HEIGHT_GROWTH`).
const RATIO_SLACK := 0.5 / 16.0 + 0.001


func describe() -> Dictionary:
	return {
		"name": "A light's pool is coded for the toon light by its height and its rim",
		"description": "Every piece's and fixture's 3D light carries its slope, room, street flag, "
			+ "height-to-rim ratio and height in light_specular, which the toon light reads "
			+ "back to shape the pool on the floor whatever the height.",
		"tags": ["lighting", "3d"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var lighting := Probe.light(t, t.rooms)
	if lighting == null:
		return
	var checked := 0
	for l: OmniLight3D in lighting.lights():
		_check(t, l)
		checked += 1
	t.check(checked > 0, "the house has lights to read back (%d)" % checked)
	var fixture_ratios := {}
	for f: Dictionary in lighting.fixtures():
		var coded := Probe.decode(f["light"])
		fixture_ratios[snappedf(coded["height"], 1.0)] = true
		t.check(
			coded["height"] > Lighting3DConfig.fixture_height / ToonLight.HEIGHT_GROWTH
				and coded["height"] < Lighting3DConfig.fixture_height * ToonLight.HEIGHT_GROWTH,
			"the fixture of %s is coded at its cast height (%.0f)" % [f["room"], coded["height"]],
		)


## `l`'s code reads back as what it was built with.
func _check(t: TestContext, l: OmniLight3D) -> void:
	var coded := Probe.decode(l)
	var height := float(l.get_meta(&"height"))
	var rim := sqrt(maxf(l.omni_range * l.omni_range - height * height, 0.0))
	t.expect_near(
		coded["ratio"], height / rim, RATIO_SLACK + 0.02 * height / rim,
		"%s: its height over its pool's rim reads back" % l.name,
	)
	t.check(
		coded["height"] <= maxf(height, ToonLight.HEIGHT_FROM) * ToonLight.HEIGHT_GROWTH
			and coded["height"] >= height / ToonLight.HEIGHT_GROWTH,
		"%s: its height reads back (%.1f for %.1f)" % [l.name, coded["height"], height],
	)
	t.expect_eq(int(coded["code"]) >> 1, int(l.get_meta(&"room")), "%s: its room" % l.name)
	t.expect_eq(coded["kind"], 0.0, "%s is a lamp's light, not a flash" % l.name)
	t.check(coded["slope"] == 1.0 or coded["slope"] == 2.0, "%s: its slope is 1 or 2" % l.name)
