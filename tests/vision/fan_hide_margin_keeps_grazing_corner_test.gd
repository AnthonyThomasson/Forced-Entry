extends GameTest
## V1 (`docs/player-vision.md`): a corner the fan has not proved hidden is cast. The fan proves a
## corner hidden when the two rays either side of it met one convex shape nearer than the corner,
## and the engine's hit positions are off a shape by up to about 0.02 px, so a corner within a hair
## of one of those rays (a grazing view of a dented face) can be called hidden while the line to it
## passes the shape's tip clear. A shelf stands east of the eye; the eye's level lies 0.005 px
## above the shelf's top face, so the corner at its east end is 1.6e-5 rad (a hair) off the fan's
## centre ray, which the engine (here: `NoisyRay`) says struck the shelf's west face 0.0175 px away
## from where it does. The corner is in plain sight (a ray to 1 px short of it is clear), so it
## gets its rays; the shelf's far south-east corner, a clear 0.005 rad from the nearest fan ray,
## is still proved hidden and gets none.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Cone := preload("res://scenes/vision/view_cone.gd")
const Noisy := preload("res://tests/_vision/noisy_sight_ray.gd")
## The shelf (40 wide, 80 tall, centred here): its corners are at x 430 and 470, y 210 and 290.
const SHELF_AT := Vector2(450, 250)
const EYE := Vector2(150, 209.99)
const TIP := Vector2(470, 210)
## The corners that get rays: the north-west (280 px away, no nearer than the corner, not hidden),
## the south-west likewise, and the tip. The south-east one is hidden by the fan.
const CORNER_RAYS := 3


func describe() -> Dictionary:
	return {
		"name": "The fan hides no corner a hair off one of its own rays",
		"description": "A shelf's tip a hair off the fan's centre ray, whose hit the engine "
			+ "reports 0.02 px off the shelf, is cast; a corner clear of every ray stays hidden.",
		"tags": ["vision"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(80_000, 80_000, 100, 100), { "walls": false })
	s.switch(&"nav.rebake", false)
	var shelf: Dictionary = WorldGen.object_definition("bookshelf").duplicate()
	shelf["anchored"] = true
	s.object(&"shelf", shelf, SHELF_AT)


func run(t: TestContext) -> void:
	await t.frames(3)
	var sight := {
		"fov_degrees": Probe.FOV,
		"view_distance": Probe.REACH,
		"awareness_radius": Probe.BUBBLE,
		"see_over_coverage": Probe.SEE_OVER,
	}
	var short := EYE + (TIP - EYE) * ((EYE.distance_to(TIP) - 1.0) / EYE.distance_to(TIP))
	t.require(
		Probe.blocker(t, EYE, short, []).is_empty(),
		"premise: the tip is in plain sight (the line to 1 px short of it is clear)",
	)
	var cone := Cone.new()
	var ray := Noisy.new()
	cone.set("_ray", ray)
	cone.rebuild(Probe.space(t), EYE, Vector2.RIGHT, [], sight)
	t.require(ray.noisy == 1, "premise: the fan's centre ray was answered with a noisy hit")
	t.check(
		cone.corner_rays == CORNER_RAYS,
		"the corner rays are the shelf's three corners not hidden, the tip among them (%d cast)"
		% cone.corner_rays,
	)
