extends GameTest
## The player's view composite in the 3D render mode (#193, interface 25): the 2D memory capture is
## off there, so the memory is blank and outside the cone the composite would be black. Until
## phase 3 draws the memory from the 3D scene, the composite instead dims what is outside the cone
## by `RenderConfig.unseen_dim` (0: not at all, 1: black) so the 3D ground stays readable. The
## picture itself is judged in `general/render_3d_turn_windowed`; here, the wiring: how much of
## the black the shader lays outside the cone, in 2D (all of it, as ever) and in 3D (the dim).

const Composite := preload("res://scenes/vision/view_composite.gd")
## The shader's opacity outside the cone where nothing was seen: 1 is the black of the 2D view.
const UNSEEN := "unseen_alpha"


func describe() -> Dictionary:
	return {
		"name": "The view composite dims what is outside the cone in 3D, blacks it in 2D",
		"description": "In the 2D render mode the composite is black where nothing was seen; with "
			+ "the 3D view on it lays RenderConfig.unseen_dim over the unseen ground instead, "
			+ "and the amount is tunable.",
		"tags": ["vision", "render", "3d"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(GroundLayer, &"enabled", false)
	s.set_static(RenderConfig, &"unseen_dim", 0.5)


func run(t: TestContext) -> void:
	t.expect_eq(_opacity(t, false), 1.0, "in 2D the unseen ground is black, as it always was")
	var dim := _opacity(t, true)
	t.check(dim > 0.0 and dim < 1.0, "in 3D the unseen ground is dimmed, not black (%s)" % dim)
	RenderConfig.unseen_dim = 0.25
	var lighter := _opacity(t, true)
	t.check(lighter < dim, "a smaller dim amount is a lighter unseen ground (%s)" % lighter)
	await t.frames(1)


## What a composite built with the 3D view on or off lays over the unseen ground.
func _opacity(t: TestContext, in_3d: bool) -> float:
	GroundLayer.enabled = in_3d
	var composite: Node2D = Composite.new()
	t.world.add_child(composite)
	var texture := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	composite.build(texture, texture, Rect2(0, 0, 4, 4), 1.0, Vector2i(4, 4))
	var material := composite.material as ShaderMaterial
	var opacity: float = material.get_shader_parameter(UNSEEN)
	composite.queue_free()
	return opacity
