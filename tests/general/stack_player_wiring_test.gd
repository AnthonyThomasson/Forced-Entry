extends GameTest
## Desired (ticket #41): the composition root gives the human the stack radio.
## `MatchBuilder.bind_player` (the helper `main.gd` uses, beside `bind_npc`) attaches a
## `PlayerStack` to the player, handed the house's rooms and doorways, and returns it for the
## markers to watch.


func describe() -> Dictionary:
	return {
		"name": "Main gives the human the stack radio",
		"description": "bind_player attaches a PlayerStack child to the player, with the house's "
			+ "doorways, and returns it.",
		"tags": ["setup", "match", "stack"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.house(18)
	s.actor(&"me", &"puppet", Vector2(400, 700), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var me := t.actor(&"me")
	var stack: Node = MatchBuilder.bind_player(me, t.rooms, t.world.get("openings"))
	if not t.require(stack != null, "bind_player returns the player's stack"):
		return
	t.check(stack.get_parent() == me, "the stack is a child of the player")
	t.check(stack.has_method("view"), "which the markers can read (view)")
	t.check(
		(stack.view() as Dictionary).is_empty(),
		"and which has no reservation with no team in sight",
	)
