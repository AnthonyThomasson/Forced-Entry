extends GameTest
## V4 and V12 (`docs/player-vision.md`): the seen mask is `seen_scale` texels per world px over the
## floors' bounds, at most `seen_max_side` texels a side (which is also under Godot's 16384 limit),
## so for a world wider than that allows the scale drops to fit, and the mask still maps the bounds
## edge to edge.
##
## It reads (tests/_vision/vision_probe.gd) the 3D view's seen viewport, its scale and its canvas
## transform. A long arena, 20000 px, that no scale of 0.5 fits within 2048 texels.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const BOUNDS := Rect2(0, 0, 20_000, 300)
## The spec's seen mask: texels per world px, and the most texels on a side.
const SEEN_SCALE := 0.5
const MAX_SIDE := 2048
## Godot's limit on a texture's side, px.
const LIMIT := 16_384


func describe() -> Dictionary:
	return {
		"name": "The memory scale drops to fit the texture limit",
		"description": "A floor 20000 px long cannot be remembered at the configured scale: the "
			+ "seen mask stays within its largest side and still covers the bounds edge to edge.",
		"tags": ["vision", "render", "3d"],
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
	if not t.require(view != null and view.ground != null, "the world has a 3D view"):
		return
	var seen: SubViewport = view.ground.seen
	var scale: float = view.ground.seen_texels
	t.check(
		seen.size.x <= MAX_SIDE and seen.size.y <= MAX_SIDE and seen.size.x <= LIMIT,
		"within the limit: %s" % [seen.size],
	)
	t.check(scale < SEEN_SCALE, "the scale dropped (%f)" % scale)
	t.check(
		absf(float(seen.size.x) - BOUNDS.size.x * scale) <= 1.0,
		"the memory still covers the bounds' width",
	)
	# The memory is whole texels, so the far corner falls within the last one.
	var far: Vector2 = seen.canvas_transform * BOUNDS.end
	var gap := Vector2(seen.size) - far
	t.check(
		gap.x >= 0.0 and gap.x < 1.0 and gap.y >= 0.0 and gap.y < 1.0,
		"the bounds' far corner is in the memory's last texel (%s)" % [far],
	)
