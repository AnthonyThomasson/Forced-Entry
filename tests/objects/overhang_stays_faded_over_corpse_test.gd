extends GameTest
## A corpse under an awning keeps it faded, as a living character does: the overhang fades for any
## `characters` member under its drawn area, dead or alive. A character who dies as it arrives under
## an awning, before the physics server has seen it alive, still fades it, and it stays faded.

const FADED_ALPHA := 0.25
const ALPHA_SLACK := 0.03
## How long the awning is watched after the death (the spec: at least 2 s).
const AFTER_DEATH := 2.0


func describe() -> Dictionary:
	return {
		"name": "An awning stays faded over a corpse",
		"description": "A puppet is moved under an awning and dies in the same frame: the "
			+ "awning is at the faded alpha two seconds after the death.",
		"tags": ["objects", "overhang", "awning", "fade"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.object(&"awning", "awning", Vector2(300, 150))
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
	var victim := t.actor(&"victim")
	var area: Rect2 = overhang.get_global_transform() * overhang.get_rect()
	victim.global_position = area.get_center()
	victim.take_damage(victim.health + 1.0)
	if not t.require(victim.is_dead, "the character died under the awning"):
		return
	await t.seconds(AFTER_DEATH)
	t.check(
		absf(_alpha(overhang) - FADED_ALPHA) <= ALPHA_SLACK,
		"the awning is still faded %.0f s after the death (alpha %.2f)"
			% [AFTER_DEATH, _alpha(overhang)],
	)
