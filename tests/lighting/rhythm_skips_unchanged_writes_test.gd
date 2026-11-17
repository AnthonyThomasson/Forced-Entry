extends GameTest
## Rhythms keep their clocks, but a frame that leaves a light's energy unchanged makes no engine
## write. The 3D lighting counts both: its rhythm steps and the energies it wrote.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const FRAMES := 180


func describe() -> Dictionary:
	return {
		"name": "A light rhythm skips unchanged writes",
		"description": "Every rhythm still steps each frame while a light's energy is written "
			+ "only when its value changes.",
		"tags": ["lighting", "perf"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	for i in 4:
		s.object(StringName("tube_%d" % i), "neon_tube", Vector2(100.0 + 130.0 * i, 200))
		s.object(StringName("tv_%d" % i), "tv", Vector2(100.0 + 130.0 * i, 300), { "neon": "" })
		# A rack blinks or pulses: a blink holds its energy between edges.
		s.object(StringName("rack_%d" % i), "server_rack", Vector2(100.0 + 130.0 * i, 100))


func run(t: TestContext) -> void:
	var lighting := Probe.light(t)
	if lighting == null:
		return
	await t.frames(FRAMES)
	var steps: int = lighting.rhythm_steps
	t.check(steps >= FRAMES, "every rhythm still advances on every frame (%d steps)" % steps)
	var energy: int = lighting.energy_writes
	t.check(
		energy < steps,
		"an unchanged energy is not written again (%d writes, %d steps)" % [energy, steps],
	)
