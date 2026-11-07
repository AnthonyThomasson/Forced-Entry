extends GameTest
## A decision's own look at the house is a full one (#192 rule 28): an unfamiliar NPC's idle looks
## for furniture it does not know take a third of the pieces each (`ai/perception_cadence_suite`),
## but the snapshot a decision is built from has looked at every piece in view first, so what the
## NPC knows when it decides is what it sees at that moment. Six pieces stand round the NPC, all
## inside its near bubble; its decision's snapshot is built at once, before any scheduled look has
## run.


func describe() -> Dictionary:
	return {
		"name": "A decision looks at all the furniture in view",
		"description": "An unfamiliar NPC that builds its decision snapshot knows every piece of "
			+ "furniture in its view, though its idle looks take a third of them at a time.",
		"tags": ["ai", "perception", "scripted"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.von_down()
	s.actor(&"npc", &"invader", Vector2(300, 200), { "movement:speed": 0.0 })


func run(t: TestContext) -> void:
	await t.frames(2)
	var perception: Node = t.controller(&"npc", &"debug_state").get("_perception")
	var pieces: Array = []
	for i in 6:
		var piece := Piece.new()
		t.world.add_child(piece)
		piece.global_position = Vector2(300, 200) + Vector2.from_angle(TAU * i / 6.0) * 30.0
		pieces.append(piece)
	perception.house.interactables = pieces
	var known_before: int = perception.house.known_object_ids().size()
	if not t.require(known_before < pieces.size(), "premise: the NPC has not looked at them all"):
		return
	perception.sense("", "")
	t.check(
		perception.house.known_object_ids().size() == pieces.size(),
		"the snapshot's look knows all %d pieces (knew %d)" % [pieces.size(), known_before],
	)


## A piece of furniture that offers nothing to do.
class Piece:
	extends Node2D

	func get_interactions() -> Array:
		return []
