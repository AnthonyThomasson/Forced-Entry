extends GameTest
## Rhythms keep their clocks, but a frame that leaves a light's energy or its glow unchanged makes
## no engine write. The seeded-rhythm test pins the resulting light values.

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const FRAMES := 180


func describe() -> Dictionary:
	return {
		"name": "A light rhythm skips unchanged writes",
		"description": "Every rhythm still steps each frame while energy and glow are written only "
			+ "when their values change.",
		"tags": ["lighting", "perf"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	for i in 4:
		s.object(StringName("tube_%d" % i), "neon_tube", Vector2(100.0 + 130.0 * i, 200))
		s.object(StringName("tv_%d" % i), "tv", Vector2(100.0 + 130.0 * i, 300), { "neon": "" })


func run(t: TestContext) -> void:
	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	await t.frames(FRAMES)
	var steps = lighting.get("rhythm_steps")
	if not t.require(steps != null, "the lighting counts its rhythm steps"):
		return
	t.check(steps >= FRAMES, "every rhythm still advances on every frame")
	var energy: int = lighting.get("energy_writes")
	var glow: int = lighting.get("glow_writes")
	t.check(
		energy < steps or glow < steps,
		"an unchanged energy or glow is not written again (%d / %d writes, %d steps)"
			% [energy, glow, steps],
	)
