extends GameTest
## A death wakes the awnings of the corpse's own world only: an awning at the same coordinates in
## another world (its own `World2D`, as a second match or a preview has) stays opaque.

const FADED_ALPHA := 0.25
const ALPHA_SLACK := 0.03
const AWNING_AT := Vector2(300, 150)


func describe() -> Dictionary:
	return {
		"name": "A death wakes only the awnings of its own world",
		"description": "A puppet dies under an awning; a second awning at the same spot in a "
			+ "viewport with its own world stays opaque while the first stays faded.",
		"tags": ["objects", "overhang", "awning", "fade"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.object(&"awning", "awning", AWNING_AT)
	s.actor(&"victim", &"puppet", Vector2(300, 350))


func _alpha(overhang: CanvasItem) -> float:
	var alpha := 1.0
	var node: Node = overhang
	while node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a * (node as CanvasItem).self_modulate.a
		node = node.get_parent()
	return alpha


func run(t: TestContext) -> void:
	var overhang := t.object(&"awning").find_child("Overhang", true, false) as CanvasItem
	if not t.require(overhang != null, "the awning has an Overhang"):
		return
	var view := SubViewport.new()
	view.world_2d = World2D.new()
	t.world.add_child(view)
	var other := ObjectFactory.spawn(WorldGen.object_definition("awning"), AWNING_AT, view)
	await t.frames(2)
	var other_overhang := other.find_child("Overhang", true, false) as CanvasItem
	if not t.require(other_overhang != null, "the awning in the other world has an Overhang"):
		return
	t.require(
		other_overhang.get_world_2d() != overhang.get_world_2d(),
		"the two awnings are in two worlds",
	)
	var victim := t.actor(&"victim")
	var area: Rect2 = overhang.get_global_transform() * overhang.get_rect()
	victim.global_position = area.get_center()
	victim.take_damage(victim.health + 1.0)
	if not t.require(victim.is_dead, "the character died under the awning"):
		return
	await t.seconds(1.0)
	t.check(
		absf(_alpha(overhang) - FADED_ALPHA) <= ALPHA_SLACK,
		"the awning in the corpse's world is faded (alpha %.2f)" % _alpha(overhang),
	)
	t.check(
		is_equal_approx(_alpha(other_overhang), 1.0),
		"the awning in the other world stays opaque (alpha %.2f)" % _alpha(other_overhang),
	)
