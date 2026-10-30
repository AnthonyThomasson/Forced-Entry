extends GameTest
## The defenders' ambush rule (#128, interface 21) runs for the defenders' squad alone, and never
## while the human leads it: a human-led defender squad and the invaders' AI-led squad, each hearing
## a threat its side's radio places outside its leader's room by a doorway, order no ambush.
##
## Mechanism test (scripted): the radio calls are the test's own, posted by an NPC member of each
## side. Squads declared as a match builds them (`s.squads`, `MatchBuilder.build_squads`), the
## defenders' led by a household puppet standing in for the human (`human`). Over the bare Terrace
## house: the defenders in the living room's west end, the invaders in the kitchen's east end, the
## wall between them hiding each side from the other. Premise switches: every NPC's
## `movement:speed` is 0, so each leader's room stays the one it starts in while the rule is read,
## and Von is scripted (a crew left alone walks its leader out of its room).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
## Outside by the front door: the defenders' attack comes into the living room by the hall's
## doorway.
const OUTSIDE_FRONT := Vector2(-100, 415)
## The hall's west end: the invaders' attack comes into the kitchen by a doorway too.
const IN_HALL := Vector2(300, 415)


func describe() -> Dictionary:
	return {
		"name": "The ambush rule is off for a human-led squad and for the invaders",
		"description": "A defender squad the human leads and the invaders' AI-led squad, each "
			+ "hearing a threat outside its leader's room, order no ambush (#128).",
		"tags": ["ai", "leadership", "squad", "order", "ambush", "human"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	var still := { "movement:speed": 0.0 }  # premise: each leader's room stays its own
	s.actor(&"me", &"puppet", Vector2(200, 40), { "faction": &"household" })
	s.actor(&"d1", &"defender", Vector2(60, 40), still)
	s.actor(&"d2", &"defender", Vector2(120, 60), still)
	s.actor(&"d3", &"defender", Vector2(60, 100), still)
	s.actor(&"i1", &"invader", Vector2(800, 40), still)
	s.actor(&"i2", &"invader", Vector2(800, 90), still)
	s.actor(&"i3", &"invader", Vector2(760, 60), still)
	s.von_script([{ "pick": "wait" }])
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var defenders: Node = t.world.squad(&"household")
	var invaders: Node = t.world.squad(&"invader")
	if not t.require(
			defenders != null and defenders.leader() == t.actor(&"me"),
			"premise: the defenders' squad, led by the human",
	):
		return
	if not t.require(
			invaders != null and invaders.leader() == t.actor(&"i1"),
			"premise: the invaders' squad, led by i1 (an AI)",
	):
		return
	await t.seconds(0.5)
	t.check(
		await _call(t, &"d2", &"household", OUTSIDE_FRONT) == {},
		"the human-led defenders order no ambush on a threat outside the front door",
	)
	t.check(
		await _call(t, &"i2", &"invader", IN_HALL) == {},
		"the invaders order no ambush on a threat in the hall",
	)
	t.check(
		await _call(t, &"i1", &"invader", IN_HALL + Vector2(40, 0)) == {},
		"nor on their leader's own call",
	)


## Post a COMBAT callout of `faction` from actor `speaker` placing a hostile at `target`, wait two
## frames, and return the ambush order it gave rise to, or {}.
func _call(t: TestContext, speaker: StringName, faction: StringName, target: Vector2) -> Dictionary:
	var who := t.actor(speaker)
	var before := Order.ambushes(t).size()
	EventBus.post(&"callout", {
		"speaker": who, "faction": faction, "position": who.global_position,
		"status": "", "path": "combat/t_1/engage/here", "label": "COMBAT", "target_id": 0,
		"point": who.global_position, "target_pos": target,
	})
	await t.frames(2)
	var after := Order.ambushes(t)
	return after.back() if after.size() > before else {}
