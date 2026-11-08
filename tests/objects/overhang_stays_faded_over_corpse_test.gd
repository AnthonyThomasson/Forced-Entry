extends GameTest
## A corpse under an awning keeps it faded, as a living character does: the overhang fades for any
## `characters` member under its drawn area, dead or alive. A character who dies as it arrives under
## an awning, before the physics server has seen it alive, still fades it, and it stays faded; so
## does one that stood under it and then died (dying reads as leaving); and once the corpse is
## freed the awning is opaque again and its watcher sleeps.

const OverhangVisuals := preload("res://scenes/objects/overhang_visuals.gd")
const FADED_ALPHA := 0.25
const ALPHA_SLACK := 0.03
## How long the awning is watched after the death (the spec: at least 2 s).
const AFTER_DEATH := 2.0


func describe() -> Dictionary:
	return {
		"name": "An awning stays faded over a corpse",
		"description": "A puppet is moved under an awning and dies in the same frame, another "
			+ "stands under one and then dies: each awning is at the faded alpha two seconds "
			+ "after the death; freeing the corpses lets them go opaque and the watcher sleep.",
		"tags": ["objects", "overhang", "awning", "fade"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.object(&"awning", "awning", Vector2(300, 150))
	s.object(&"awning_two", "awning", Vector2(500, 150))
	s.actor(&"victim", &"puppet", Vector2(300, 350))
	s.actor(&"stander", &"puppet", Vector2(500, 350))


func _alpha(overhang: CanvasItem) -> float:
	var alpha := 1.0
	var node: Node = overhang
	while node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a * (node as CanvasItem).self_modulate.a
		node = node.get_parent()
	return alpha


func _awning(t: TestContext, id: StringName) -> CanvasItem:
	return t.object(id).find_child("Overhang", true, false) as CanvasItem


func _centre(overhang: CanvasItem) -> Vector2:
	var area: Rect2 = overhang.get_global_transform() * overhang.get_rect()
	return area.get_center()


func run(t: TestContext) -> void:
	var overhang := _awning(t, &"awning")
	var second := _awning(t, &"awning_two")
	if not t.require(overhang != null and second != null, "the awnings have an Overhang"):
		return
	var victim := t.actor(&"victim")
	var stander := t.actor(&"stander")
	victim.global_position = _centre(overhang)
	victim.take_damage(victim.health + 1.0)
	if not t.require(victim.is_dead, "the character died under the awning"):
		return
	# The other one stands under its awning, fades it, and only then dies.
	stander.global_position = _centre(second)
	await t.seconds(0.5)
	t.require(
		absf(_alpha(second) - FADED_ALPHA) <= ALPHA_SLACK,
		"the awning fades over a living character (alpha %.2f)" % _alpha(second),
	)
	stander.take_damage(stander.health + 1.0)
	if not t.require(stander.is_dead, "the second character died under its awning"):
		return
	await t.seconds(AFTER_DEATH)
	t.check(
		absf(_alpha(overhang) - FADED_ALPHA) <= ALPHA_SLACK,
		"the awning is still faded %.0f s after the death (alpha %.2f)"
			% [AFTER_DEATH, _alpha(overhang)],
	)
	t.check(
		absf(_alpha(second) - FADED_ALPHA) <= ALPHA_SLACK,
		"the awning over one that stood there first is still faded %.0f s after its death "
			% AFTER_DEATH + "(alpha %.2f)" % _alpha(second),
	)
	victim.queue_free()
	stander.queue_free()
	await t.seconds(0.5)
	t.check(
		is_equal_approx(_alpha(overhang), 1.0) and is_equal_approx(_alpha(second), 1.0),
		"both awnings are opaque once the corpses are freed (alpha %.2f, %.2f)"
			% [_alpha(overhang), _alpha(second)],
	)
	await t.frames(3)
	var reads: int = OverhangVisuals.FadeWatcher.group_reads
	await t.frames(10)
	t.expect_eq(
		OverhangVisuals.FadeWatcher.group_reads,
		reads,
		"the watcher sleeps once the corpses are gone",
	)
