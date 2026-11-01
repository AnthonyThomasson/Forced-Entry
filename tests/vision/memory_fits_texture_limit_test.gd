extends GameTest
## V4 (`docs/player-vision.md`): the memory is `memory_scale` texels per world px over the floors'
## bounds, but a texture is at most 16384 px across (Godot's limit), so for a world wider than that
## allows the scale drops to fit, and the memory still maps the bounds edge to edge.
##
## It reads (tests/_vision/vision_probe.gd) the view's memory, its scale and the memory's canvas
## transform. A long arena, 20000 px, that no scale of 1 or more fits.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const BOUNDS := Rect2(0, 0, 20_000, 300)
## Godot's limit on a texture's side, px.
const LIMIT := 16_384


func describe() -> Dictionary:
	return {
		"name": "The memory scale drops to fit the texture limit",
		"description": "A floor 20000 px long cannot be remembered at the configured scale: the "
			+ "memory stays within 16384 px and still covers the bounds edge to edge.",
		"tags": ["vision"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(BOUNDS)
	s.actor(&"eye", &"puppet", Vector2(500, 150))
	s.switch(&"vision.enabled", true)
	s.view(&"eye")


func run(t: TestContext) -> void:
	await t.frames(3)
	var view := Probe.view(t)
	if not t.require(view != null and view.memory() != null, "the world has a view with a memory"):
		return
	var memory := view.memory()
	t.check(
		memory.size.x <= LIMIT and memory.size.y <= LIMIT,
		"within the limit: %s" % [memory.size],
	)
	t.check(view.memory_scale() < VisionConfig.memory_scale, "the scale dropped")
	t.check(
		absf(float(memory.size.x) - BOUNDS.size.x * view.memory_scale()) <= 1.0,
		"the memory still covers the bounds' width",
	)
	# The memory is whole texels, so the far corner falls within the last one.
	var far: Vector2 = memory.canvas_transform * BOUNDS.end
	var gap := Vector2(memory.size) - far
	t.check(
		gap.x >= 0.0 and gap.x < 1.0 and gap.y >= 0.0 and gap.y < 1.0,
		"the bounds' far corner is in the memory's last texel (%s)" % [far],
	)
