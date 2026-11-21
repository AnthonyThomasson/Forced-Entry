extends "res://tests/vision/fan_hide_margin_keeps_grazing_corner_test.gd"
## `vision/fan_hide_margin_keeps_grazing_corner` with the catalogue's bookshelf, hollow since the
## unbake (#194 unbake-b, D21, `docs/player-vision.md` V1): the same shelf, now its boards, sides
## and back, stands where the solid one did, anchored. The fan's corner rule is about the shapes
## the eye sees: the corner at the shelf's east end is a hair off the centre ray and is still cast,
## and the fan casts at least the corners in plain sight.


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "The fan hides no corner a hair off one of its own rays (the real bookshelf)"
	d["description"] = (
		"The same grazing tip as with the solid shelf, the catalogue's hollow bookshelf in "
		+ "its place: the tip is cast, and corners the fan proved hidden are not."
	)
	return d


func configure(s: TestSetup) -> void:
	s.arena(Rect2(80_000, 80_000, 100, 100), { "walls": false })
	s.switch(&"nav.rebake", false)
	var shelf: Dictionary = WorldGen.object_definition("bookshelf").duplicate()
	shelf["anchored"] = true
	s.object(&"shelf", shelf, SHELF_AT)


## The corner rays of a view's fan from `EYE` with `ray` as its sight ray (the cone's own if null).
func _corner_rays(t: TestContext, ray: Object) -> int:
	var sight := {
		"fov_degrees": Probe.FOV,
		"view_distance": Probe.REACH,
		"awareness_radius": Probe.BUBBLE,
		"eye_height": Probe.SEE_OVER,
	}
	var cone := Cone.new()
	if ray != null:
		cone.set("_ray", ray)
	cone.rebuild(Probe.space(t), EYE, Vector2.RIGHT, [], sight)
	return cone.corner_rays


## The hollow shelf has a corner at each of its boards, so the count is not the solid one's: the
## noisy centre ray strikes the west side board, which hides (as a real strike would) the corners
## of the boards behind it that a clean engine's grazing ray leaves cast. What the rule promises
## still holds: the fan casts at least the three corners the solid shelf has in plain sight (the
## north-west, the south-west and the tip), and fewer than a clean engine's fan only by corners
## that board hides.
func run(t: TestContext) -> void:
	await t.frames(3)
	var noisy := Noisy.new()
	var with_noise := _corner_rays(t, noisy)
	t.require(noisy.noisy == 1, "premise: the fan's centre ray was answered with a noisy hit")
	var clean := _corner_rays(t, null)
	t.check(
		with_noise >= CORNER_RAYS,
		"the fan casts the shelf's three corners in plain sight (%d cast)" % with_noise,
	)
	t.check(with_noise <= clean, "and no more than a clean engine's fan (%d cast)" % clean)
