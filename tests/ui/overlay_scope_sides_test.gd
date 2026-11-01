extends GameTest
## The overlay bar's "Show on" scope in a test world (the test runner's bar): a world with two
## defenders (faction household), two invaders and the human (a puppet, no AI controller), the
## per-NPC overlays shown only on the NPCs the scope admits: `defenders`, `invaders` or `all`. A
## toggle reaches only the NPCs the scope admits, changing the scope re-applies the toggles at once,
## and the human never gets an overlay: a stand-in overlay on it records every flag written to it,
## and none ever is.

const InspectorProbe := preload("res://tests/_ui/inspector_probe.gd")
const SIDES := InspectorProbe.SIDES


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
	var stand_in := OverlayStandIn.new()
	t.actor(&"human").add_child(stand_in)
	var everyone := ["d1", "d2", "i1", "i2"]
	world.call("set_overlay", "show_vision", true)
	_expect_lit(t, "show_vision", everyone, "scope all: every NPC shows")

	world.call("set_overlay_scope", "defenders")
	_expect_lit(t, "show_vision", ["d1", "d2"], "scope defenders: only the defenders show")

	world.call("set_overlay_scope", "invaders")
	_expect_lit(t, "show_vision", ["i1", "i2"], "scope invaders: only the invaders show")

	world.call("set_overlay", "show_contacts", true)
	_expect_lit(t, "show_contacts", ["i1", "i2"], "a toggle under invaders reaches them only")
	_expect_lit(t, "show_vision", ["i1", "i2"], "and leaves the vision overlays as they were")

	world.call("set_overlay_scope", "all")
	_expect_lit(t, "show_contacts", everyone, "scope all again: every NPC shows both")
	_expect_lit(t, "show_vision", everyone, "the vision overlays too")

	t.check(
		stand_in.written.is_empty(),
		"the human's overlay was never written to (%s)" % [stand_in.written],
	)


## The actors whose overlay of `flag` is on are `ids`.
func _expect_lit(t: TestContext, flag: String, ids: Array, message: String) -> void:
	t.expect_eq(InspectorProbe.lit(t, flag), ids, message)


## An overlay on a character with no AI controller: it has the flags' properties, so anything that
## applies a flag to the character reaches it, and it records each write (on or off).
class OverlayStandIn:
	extends Node

	var written: Array = []
	var show_vision := false:
		set(value):
			written.append(["show_vision", value])
			show_vision = value
	var show_contacts := false:
		set(value):
			written.append(["show_contacts", value])
			show_contacts = value
