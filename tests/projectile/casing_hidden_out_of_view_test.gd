extends GameTest
## A casing is shown by the player's view only once seen (#193 vision-mask, `docs/player-vision.md`
## V5, V6 and V12): the 3D casing batch draws one tossed out of sight no size at all, and one lying
## where nothing has seen it likewise; once the cone has reached it, it is whole where it lies and
## stays so after the cone moves on (remembered). The seen area is set by hand (a box, as the view
## publishes it); a casing tossed inside it keeps its size all the way. Asserted at the layer's
## seam (`ProjectileMeshes.install`: `casing_frame`).

const SCRATCH := "user://settings_casing_hidden_test.json"
## The area the view shows live, and a spot well inside it and one well outside.
const SEEN := Rect2(100, 100, 400, 400)
const IN_VIEW := Vector2(300, 300)
const OUT_OF_VIEW := Vector2(800, 300)
## A casing tossed arcs for about this long (s).
const TOSS_FRAMES := 40


func describe() -> Dictionary:
	return {
		"name": "A casing tossed out of the player's view is drawn no size, one in view is whole",
		"description": "With a seen area set, a casing tossed outside it has a zero-size part "
			+ "while it flies and lying until the cone reaches it, then its whole size for good; "
			+ "one tossed inside keeps its size.",
		"tags": ["mirror", "3d", "render", "projectile", "casing", "vision"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	var layer := ProjectileMeshes.install(mirror, t.world)
	mirror.mirror(t.world)
	var box := _box(SEEN)
	SeenArea.set_area([box], SEEN)
	CasingSpawner.spawn(IN_VIEW, Vector2.RIGHT, t.world)
	await t.frames(3)
	t.check(layer.casing_count() == 1, "premise: the casing in view is in the batch")
	t.check(layer.casing_frame(0).basis.get_scale().x > 0.9, "tossed in view it keeps its size")
	await t.frames(TOSS_FRAMES)
	CasingSpawner.spawn(OUT_OF_VIEW, Vector2.RIGHT, t.world)
	await t.frames(3)
	t.expect_eq(layer.casing_count(), 2, "premise: the casing out of view is in the batch too")
	var hidden := layer.casing_frame(1)
	t.check(hidden.basis.get_scale().x < 0.01, "tossed out of view it is drawn no size")
	await t.frames(TOSS_FRAMES)
	t.check(layer.casing_frame(0).basis.get_scale().x > 0.9, "the one in view lies, whole")
	t.check(
		layer.casing_frame(1).basis.get_scale().x < 0.01,
		"lying where nothing has seen it, it is still drawn no size",
	)
	t.check(layer.is_processing(), "and the layer watches for the cone to reach it")
	SeenArea.set_area([_box(Rect2(700, 200, 200, 200))], Rect2(700, 200, 200, 200))
	await t.frames(2)
	t.check(layer.casing_frame(1).basis.get_scale().x > 0.9, "the cone reaches it: whole")
	SeenArea.set_area([box], SEEN)
	await t.frames(2)
	t.check(
		layer.casing_frame(1).basis.get_scale().x > 0.9,
		"the cone moves on: it stays whole where it lies",
	)
	t.check(not layer.is_processing(), "and nothing runs once they are all seen")
	await _flies_out_of_view(t, layer, box)
	SeenArea.clear()


## The polygon of `rect`, as the view publishes a cone.
func _box(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]
	)


## A casing tossed in view and still in the air when the cone moves off it is not seen where it
## lands: it is no size there until the cone reaches it again.
func _flies_out_of_view(t: TestContext, layer: ShotLayer, box: PackedVector2Array) -> void:
	var slot := layer.casing_count()
	CasingSpawner.spawn(IN_VIEW, Vector2.RIGHT, t.world)
	await t.frames(3)
	t.check(layer.casing_frame(slot).basis.get_scale().x > 0.9, "premise: tossed in view, whole")
	var away := Rect2(700, 500, 100, 100)
	SeenArea.set_area([_box(away)], away)
	await t.frames(TOSS_FRAMES)
	t.check(
		layer.casing_frame(slot).basis.get_scale().x < 0.01,
		"it flew out of view and lies unseen: no size",
	)
	SeenArea.set_area([box], SEEN)
	await t.frames(2)
	t.check(layer.casing_frame(slot).basis.get_scale().x > 0.9, "the cone reaches it again: whole")
