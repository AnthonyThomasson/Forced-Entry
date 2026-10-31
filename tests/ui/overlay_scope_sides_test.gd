extends GameTest
## The overlay bar's "Show on" scope in a test world (the test runner's bar): a world with two
## defenders (faction household), two invaders and the human (a puppet, no AI controller), the
## per-NPC overlays shown only on the NPCs the scope admits: `defenders`, `invaders` or `all`. A
## toggle reaches only the NPCs the scope admits, changing the scope re-applies the toggles at once,
## and the human never gets an overlay.

const SIDES := {
	&"d1": &"defender", &"d2": &"defender", &"i1": &"invader", &"i2": &"invader",
}


func describe() -> Dictionary:
	return {
		"name": "The overlay scope shows overlays on one side or on all",
		"description": "Two defenders, two invaders and a human: with the vision overlay on, the "
			+ "scope defenders turns on only the defenders' overlays, invaders only the invaders', "
			+ "all every NPC's; a contacts toggle under invaders reaches only the invaders; the "
			+ "human has no overlay.",
		"tags": ["ui", "overlay"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1600, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"ai.vision", false)
	s.von_down()
	for i in SIDES.size():
		var id: StringName = SIDES.keys()[i]
		s.actor(id, SIDES[id], Vector2(100 + 400 * i, 250), { "movement:speed": 0.0 })
	s.actor(&"human", &"puppet", Vector2(1500, 450), { "faction": &"player" })


func run(t: TestContext) -> void:
	var world: Node2D = t.world
	world.call("set_overlay", "show_vision", true)
	t.expect_eq(_lit(t, "show_vision"), ["d1", "d2", "i1", "i2"], "scope all: every NPC shows")

	world.call("set_overlay_scope", "defenders")
	t.expect_eq(_lit(t, "show_vision"), ["d1", "d2"], "scope defenders: only the defenders show")

	world.call("set_overlay_scope", "invaders")
	t.expect_eq(_lit(t, "show_vision"), ["i1", "i2"], "scope invaders: only the invaders show")

	world.call("set_overlay", "show_contacts", true)
	t.expect_eq(_lit(t, "show_contacts"), ["i1", "i2"], "a toggle under invaders reaches them only")
	t.expect_eq(_lit(t, "show_vision"), ["i1", "i2"], "and leaves the vision overlays as they were")

	world.call("set_overlay_scope", "all")
	t.expect_eq(
		_lit(t, "show_contacts"), ["d1", "d2", "i1", "i2"], "scope all again: every NPC shows both",
	)
	t.expect_eq(_lit(t, "show_vision"), ["d1", "d2", "i1", "i2"], "the vision overlays too")

	var human := t.actor(&"human")
	t.check(_overlay_children(human, "show_vision").is_empty(), "the human has no overlay at all")


## The ids of the actors whose overlay of `flag` is on, in the order of `SIDES`.
func _lit(t: TestContext, flag: String) -> Array:
	var out: Array = []
	for id: StringName in SIDES:
		for overlay in _overlay_children(t.actor(id), flag):
			if bool(overlay.get(flag)):
				out.append(String(id))
	return out


## Every child of `character` that has the property `flag`.
func _overlay_children(character: Node, flag: String) -> Array:
	return character.get_children().filter(func(c): return flag in c)
