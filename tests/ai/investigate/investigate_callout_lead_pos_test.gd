extends GameTest
## The INVESTIGATE callout's `lead_pos` (interface 10, the defenders' ambush rule, #128 rule 3): an
## INVESTIGATE decision, here STAY, radios the spot of the freshest lead the NPC weighed that places
## a hostile, an ally's support lead skipped (its spot is the ally, whose own COMBAT callout carries
## `target_pos`).
##
## Mechanism test (`von_script`: one mechanism). A defender in the bare Terrace house's living room,
## by its west wall, hears two walkers' steps outside that wall (the test's own `&"footfall"`
## events, from two invader puppets standing out of its sight), the northern one first, the
## southern one a second later; then an ally on its side radios a fight (a COMBAT callout the test
## posts from a household puppet in the room), the freshest lead of all. Von is scripted to take
## INVESTIGATE and decline the leads (STAY). Its INVESTIGATE – STAY callout carries `lead_pos` at
## the southern walker's step, not the ally's spot nor the older step. Premise switch: the
## defender's `movement:speed` is 0.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const DEFENDER_AT := Vector2(100, 160)
## The steps heard, outside the living room's west wall, within earshot of a walk (250 px).
const OLDER_STEP := Vector2(-60, 60)
const FRESHER_STEP := Vector2(-60, 260)
const ALLY_AT := Vector2(320, 120)
## How near the step `lead_pos` must lie (the lead's point is snapped onto the navmesh).
const NEAR := 30.0


func describe() -> Dictionary:
	return {
		"name": "An INVESTIGATE callout radios the freshest hostile lead's spot",
		"description": "A defender hears two walkers outside, then an ally's fight on the radio; "
			+ "scripted to STAY, its INVESTIGATE callout carries lead_pos at the fresher step, the "
			+ "ally's support lead skipped (#128).",
		"tags": ["ai", "investigate", "hearing", "radio", "ambush", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	# Premise: the defender stays where it hears the steps (a defender with nothing to do searches
	# the house, out of earshot of the wall).
	var still := { "facing": Vector2.RIGHT, "movement:speed": 0.0 }
	s.actor(&"d", &"defender", DEFENDER_AT, still)
	s.actor(&"ally", &"puppet", ALLY_AT, { "faction": &"household" })
	s.actor(&"w1", &"puppet", OLDER_STEP, { "faction": &"invader", "max_health": 1_000_000.0 })
	s.actor(&"w2", &"puppet", FRESHER_STEP, { "faction": &"invader", "max_health": 1_000_000.0 })
	s.von_script([
		{ "pick": "investigate" }, { "pick": "stay" }, { "pick": "idle" }, { "pick": "wait" },
	])


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var brain := t.controller(&"d", &"debug_memory")
	await t.seconds(1.0)
	_step(t.actor(&"w1"), OLDER_STEP)
	await t.seconds(1.0)
	_step(t.actor(&"w2"), FRESHER_STEP)
	await t.seconds(0.5)
	var heard: Array = brain.debug_memory().get("footsteps", [])
	if not t.require(heard.size() == 2, "premise: the defender heard both walkers (%s)" % [heard]):
		return
	var ally := t.actor(&"ally")
	EventBus.post(&"callout", {
		"speaker": ally, "faction": &"household", "position": ally.global_position,
		"status": "", "path": "combat/t_1/engage/here", "label": "COMBAT", "target_id": 0,
		"point": ally.global_position, "target_pos": Vector2(400, 60),
	})
	var calls := func(): return t.events_of(&"callout", func(c): return (
		c.get("speaker") == d and String(c.get("path", "")).begins_with("investigate/stay")
	))
	if not t.require(
			await t.until(func(): return not calls.call().is_empty(), 15.0),
			"the defender took INVESTIGATE – STAY and radioed it",
	):
		return
	var asked: Array = DecisionStub.requests.filter(
		func(r): return String(r["question"]).begins_with("What should you check first"),
	)
	if not t.require(
			not asked.is_empty()
				and asked[-1]["options"].any(func(id): return String(id).begins_with("lead_ally")),
			"premise: the ally's support lead was among the leads weighed (%s)"
				% [asked[-1]["options"] if not asked.is_empty() else []],
	):
		return
	var said: Dictionary = calls.call()[-1]
	var at: Variant = said.get("lead_pos")
	if not t.require(at is Vector2, "the callout carries lead_pos (%s)" % [said]):
		return
	t.check(
		(at as Vector2).distance_to(FRESHER_STEP) < NEAR,
		"lead_pos is the fresher step, %s (at %s)" % [FRESHER_STEP, at],
	)


## A walk step by `walker` at `pos`, as the character's footsteps post it (interface 10).
func _step(walker: Node, pos: Vector2) -> void:
	EventBus.post(&"footfall", {
		"position": pos, "character": walker, "running": false, "crouched": false,
	})
