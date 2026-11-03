extends GameTest
## A district's elevator lobby is an ordinary room of the house the match is fought in (#182, the
## brief's item 4): defenders may spawn there. The match is built as Main builds one over the
## `bodega_tower` plan with a crowd of defenders, and one of them stands in the lobby (the room of
## type `elevator_lobby`, empty of pieces), on its floor, alive and bound to the house's rooms. The
## seed is pinned (placement draws a room at random): seed 7 with these twelve defenders puts one in
## the lobby, which is what the test needs to show it can happen.

const PLAN := "bodega_tower"
const SEED := 7
const DEFENDERS := 12
const INVADERS := 1


func describe() -> Dictionary:
	return {
		"name": "A defender can spawn in the elevator lobby",
		"description": "A district match over a tower plan with twelve defenders: a defender "
			+ "stands in the elevator lobby, in the house's rooms like any other.",
		"tags": ["setup", "match", "district", "spawn", "lobby"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED, PLAN)
	s.von_down()
	s.declared_match({
		"defenders": { "count": DEFENDERS },
		"invaders": { "count": INVADERS },
	})


func run(t: TestContext) -> void:
	var lobbies: Array = t.rooms.filter(
		func(r: Dictionary) -> bool: return r["type"] == "elevator_lobby",
	)
	if not t.require(lobbies.size() == 1, "premise: the house has one elevator lobby"):
		return
	var lobby: Rect2 = lobbies[0]["rect"]
	var defenders: Array = t.world.match_handle["combatants"].filter(
		func(c: Node) -> bool: return c.get("faction") == MatchBuilder.DEFENDER_FACTION,
	)
	if not t.require(defenders.size() == DEFENDERS, "premise: every defender is placed"):
		return
	var inside: Array = defenders.filter(
		func(c: Node2D) -> bool: return lobby.has_point(c.global_position),
	)
	t.trace("defenders in the lobby", inside.size())
	if not t.require(not inside.is_empty(), "a defender stands in the elevator lobby"):
		return
	await t.seconds(1.0)
	for defender: Node2D in inside:
		t.check(not defender.is_dead, "%s is alive in the lobby" % defender.name)
		var brain := TestContext.controller_of(defender)
		t.check(
			brain != null and brain.rooms == t.rooms,
			"%s is bound to the house's rooms" % defender.name,
		)
