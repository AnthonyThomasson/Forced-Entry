extends GameTest
## #193 phase 3 (L10 in 3D): with the lighting switch off (`lighting.enabled`) the 3D render builds
## no light, no matter what the world holds: no OmniLight3D, and the sky is too dim to show; the art
## is lit flat, as painted (the toon ambient is white).
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `lights()`, `sun()`; Art's
## `ToonLight`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "With the lighting off the 3D render builds no light and lights the art flat",
		"description": "No OmniLight3D is built for the lamp and the tube, the ambient is white "
			+ "and "
			+ "the one directional light is too dim to show.",
		"tags": ["lighting", "3d"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"lighting.enabled", false)
	s.object(&"lamp", "lamp", Vector2(450, 150), { "neon": "" })
	s.object(&"tube", "neon_tube", Vector2(450, 400))


func run(t: TestContext) -> void:
	var lighting := Probe.light(t)
	if lighting == null:
		return
	t.check(lighting.lights().is_empty(), "no OmniLight3D is built")
	t.check(lighting.fixtures().is_empty(), "no fixture is built")
	t.check(
		ToonLight.ambient().is_equal_approx(Color.WHITE),
		"the art is lit flat (the ambient is white)",
	)
	t.check(
		lighting.sun() != null and lighting.sun().light_energy < 0.05,
		"the one sun is too dim to show",
	)
