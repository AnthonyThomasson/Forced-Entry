extends GameTest
## A teammate's radio claim that lands while a snapshot is being built is seen when the walk begins:
## the decision job reads the callouts again as its throw piece ends, the last thing before the
## walk (`AgentPerception.reread_claims`) and the snapshot's flank sides, their summary and the
## allies section are what a snapshot built after the claim holds, so two NPCs going for one target
## take different sides even when their decisions are spread over frames. A claim that was heard
## before the build began, or none at all, changes nothing.
##
## The living room as in `ai/flank/flank_side_held_by_radio`: the invader by the hall door sees a
## household puppet mid-room; an ally in the kitchen, out of its sight, radios the target's left
## after the snapshot was built.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(150, 330)
const TARGET_POS := Vector2(330, 170)


func describe() -> Dictionary:
	return {
		"name": "A claim heard during a build is seen as the walk begins",
		"description": "A snapshot built before a teammate's radio claim, its callouts read "
			+ "again: the claimed side reads taken by it and equals the snapshot built after "
			+ "the claim; read again with nothing new, nothing changes.",
		"tags": ["ai", "decision", "flank", "callout", "snapshot", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, { "look_at": TARGET_POS })
	Flank.target(s, &"target", TARGET_POS, NPC_POS)
	Flank.ally(s, &"radio_ally", Vector2(700, 110))


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var perception: Node = brain.get("_perception")
	var goal: String = brain.get("goal")
	var target_id: int = t.actor(&"target").get_instance_id()
	var built := _build(perception, goal)
	var before := _left(built, target_id)
	if not t.require(not before.is_empty(), "set-up: the left side was weighed"):
		return
	t.expect_eq(before["tags"]["held_by"], "", "premise: the side is free as the build ends")
	# Nothing new heard: reading the callouts again changes nothing.
	var sides: Dictionary = built["options"]["per_target"][target_id]["flank_sides"]
	var untouched: Dictionary = sides.duplicate(true)
	perception.reread_claims(built)
	t.expect_eq(
		built["options"]["per_target"][target_id]["flank_sides"], untouched,
		"nothing new on the radio: the sides are as built",
	)
	var left := Flank.side_point(TARGET_POS, (NPC_POS - TARGET_POS).normalized(), "left")
	Flank.radio(t, &"radio_ally", left)
	await t.frames(3)
	t.expect_eq(
		_left(
			built,
			target_id,
		)["tags"]["held_by"], "", "the snapshot built before is still as it was",
	)
	perception.reread_claims(built)
	var after := _left(built, target_id)
	t.expect_eq(after["tags"]["held_by"], "radio_ally (radio)", "the left side is the ally's")
	t.check(
		String(after["desc"]).contains("taken by radio_ally (radio)"),
		"its description says so (%s)" % after["desc"],
	)
	_equals_a_fresh_build(t, perception, goal, built, target_id)


## `built` (its claim read again) is what a snapshot built after the claim is: the flank sides, the
## allies and flanks sections, the stack fact.
func _equals_a_fresh_build(
	t: TestContext, perception: Node, goal: String, built: Dictionary, target_id: int
) -> void:
	var fresh := _build(perception, goal)
	t.expect_eq(
		built["options"]["per_target"][target_id]["flank_sides"],
		fresh["options"]["per_target"][target_id]["flank_sides"],
		"the flank sides equal a snapshot built after the claim",
	)
	t.expect_eq(built["sections"]["allies"], fresh["sections"]["allies"], "the allies section")
	t.expect_eq(built["sections"]["flanks"], fresh["sections"]["flanks"], "the flanks section")
	t.expect_eq(
		built["facts"]["stack_has_stun"],
		fresh["facts"]["stack_has_stun"],
		"the stack fact",
	)


## A snapshot built piece by piece, as the decision job builds one.
func _build(perception: Node, goal: String) -> Dictionary:
	var staged = perception.begin_sense(goal, "", 0)
	while not staged.done():
		staged.step()
	return staged.result()


## The flank option of the target's left side in `snapshot` (as the planner reads it: `tags`,
## `desc`), or {}.
func _left(snapshot: Dictionary, target_id: int) -> Dictionary:
	var group: Dictionary = snapshot["options"]["per_target"][target_id]["flank_sides"]
	for o: Dictionary in group["options"]:
		if o["id"] == "side_left":
			return o
	return {}
