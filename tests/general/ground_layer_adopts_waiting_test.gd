extends GameTest
## A debug overlay made while no ground layer stands (a test world's build, which ends before the
## session builds its 3D view) is not lost under the hidden world: it waits, and the layer, once
## made, moves it under itself with its owner as its home (#193, interface 27).


func describe() -> Dictionary:
	return {
		"name": "A ground layer made later adopts the overlays already made",
		"description": "An overlay made with no layer up (a nav-hole overlay at the world's "
			+ "build) is on its ground layer once one is made; one made after is adopted as ever.",
		"tags": ["render", "3d", "overlays"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	GroundLayer.forget()
	var early_owner := Node2D.new()
	t.world.add_child(early_owner)
	var early := Node2D.new()
	early.name = "NavHolesLike"
	early_owner.add_child(early)
	ViewLayers.overlay(early)
	await t.frames(2)
	t.require(early.get_parent() == early_owner, "premise: with no layer the overlay stays put")
	var layer := GroundLayer.shared()
	t.world.add_child(layer)
	var late_owner := Node2D.new()
	t.world.add_child(late_owner)
	var late := Node2D.new()
	late_owner.add_child(late)
	ViewLayers.overlay(late)
	await t.frames(3)
	t.check(early in GroundLayer.overlays_of(early_owner), "the overlay made before is adopted")
	t.check(early.get_parent() != early_owner, "it left its owner for the layer")
	t.check(late in GroundLayer.overlays_of(late_owner), "one made after is adopted as ever")
	GroundLayer.forget()
	layer.queue_free()
