extends GameTest
## An awning piece taken out of the tree and put back (a re-parent) still fades under a character:
## the wake-up the overhang builds for itself is rebuilt when it re-enters.

const FADED_ALPHA := 0.25
const ALPHA_SLACK := 0.03
const AWNING_AT := Vector2(300, 150)


func describe() -> Dictionary:
	return {
		"name": "An awning fades after it was taken out of the tree and put back",
		"description": "An awning piece is removed from its parent and added again; a puppet "
			+ "walked under it: the awning fades to about a quarter alpha.",
		"tags": ["objects", "overhang", "awning", "fade"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.object(&"awning", "awning", AWNING_AT)
	s.actor(&"walker", &"puppet", Vector2(300, 350))


func _alpha(overhang: CanvasItem) -> float:
	var alpha := 1.0
	var node: Node = overhang
	while node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a * (node as CanvasItem).self_modulate.a
		node = node.get_parent()
	return alpha


func run(t: TestContext) -> void:
	var piece := t.object(&"awning")
	var overhang := piece.find_child("Overhang", true, false) as CanvasItem
	if not t.require(overhang != null, "the awning has an Overhang"):
		return
	var parent := piece.get_parent()
	parent.remove_child(piece)
	await t.frames(2)
	parent.add_child(piece)
	await t.frames(2)
	var area: Rect2 = overhang.get_global_transform() * overhang.get_rect()
	t.actor(&"walker").global_position = area.get_center()
	await t.seconds(0.6)
	t.check(
		absf(_alpha(overhang) - FADED_ALPHA) <= ALPHA_SLACK,
		"the re-added awning fades over a character (alpha %.2f)" % _alpha(overhang),
	)
