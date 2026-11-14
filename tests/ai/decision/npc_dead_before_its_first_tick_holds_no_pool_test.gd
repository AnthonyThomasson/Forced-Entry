extends GameTest
## An NPC killed before its controller has ever run (a body dead before its first tick) holds
## nothing in the decision pool: it never claimed, so the next NPC claims on its very first frame.
## Two invaders see a trespasser at once with every piece priced and one unit a frame; the first is
## killed before the first physics frame.

const Probe := preload("res://tests/_ai/pool_release_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "An NPC dead before its first tick holds no pool",
		"description": "The first of two invaders is killed before its controller ever ran: the "
			+ "second claims its decision on its first frame.",
		"tags": ["ai", "decision", "scripted"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	Probe.configure(s)


func run(t: TestContext) -> void:
	var elder := t.actor(&"inv0")
	var younger := t.controller(&"inv1", &"debug_state")
	var brain := t.controller(&"inv0", &"debug_state")
	if not t.require(brain.get("_character") == null, "set-up: the elder's controller never ran"):
		return
	younger.get("_cadence").force("probe")
	elder.take_damage(1_000_000.0)
	var waited := 0
	while int(younger.debug_state()["decisions"]) == 0 and waited < 8:
		await t.frames(1)
		waited += 1
	t.require(elder.is_dead, "premise: the elder is dead")
	t.expect_eq(int(brain.debug_state()["decisions"]), 0, "the dead NPC never claimed")
	t.expect_eq(waited, 1, "the younger claimed on its first frame")
