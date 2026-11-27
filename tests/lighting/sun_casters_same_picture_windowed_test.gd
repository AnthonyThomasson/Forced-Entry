extends GameTest
## Leaving out of the sun's shadow pass what cannot shadow the street changes no pixel: in a
## district, held still, each frame is drawn as the game draws it and again with the sun casting
## from every layer. Windowed only.

const Frozen := preload("res://tests/_render/frozen_frame.gd")


func describe() -> Dictionary:
	return {
		"name": "The sun's thinned shadow pass draws the same picture",
		"description": "Held frames of a district with indoor casters left out of the sun's pass "
			+ "and with them in are the same pixel for pixel. Windowed only.",
		"tags": ["lighting", "render", "3d"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.district(4)
	s.switch(&"nav.rebake", false)
	s.lock_interaction([&"camera"])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var view := Frozen.view(t)
	var sun: DirectionalLight3D = view.lighting.sun()
	var thinned := sun.shadow_caster_mask
	# the district's pieces and items are asleep, so the indoor ones are left out
	await t.seconds(6.0)
	for turn: float in Frozen.TURNS:
		await Frozen.hold(t, view, turn)
		var as_drawn := await Frozen.picture(t)
		var few := _shadow_draws(view)
		sun.shadow_caster_mask = 0xffffffff
		var everything := await Frozen.picture(t)
		var all := _shadow_draws(view)
		sun.shadow_caster_mask = thinned
		t.require(all > few, "premise: the mask leaves draws out (%d of %d)" % [all - few, all])
		t.expect_eq(
			Frozen.differing(as_drawn, everything), 0, "at %.1f round, no pixel differs" % turn
		)
		sun.shadow_enabled = false
		var unshadowed := await Frozen.picture(t)
		sun.shadow_enabled = true
		t.check(
			Frozen.differing(as_drawn, unshadowed) > 0,
			"premise: at %.1f round the sun's shadow shows" % turn,
		)
	Frozen.release(t)


## The shadow passes' draws in the view's last frame.
func _shadow_draws(view: CanvasLayer) -> int:
	return RenderingServer.viewport_get_render_info(
		view.viewport.get_viewport_rid(),
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME,
	)
