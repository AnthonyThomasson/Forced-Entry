extends GameTest
## A decision's snapshot built in pieces (`AgentPerception.begin_sense`, stepped) is the snapshot
## `sense()` builds in one call (#208): the same facts, state sections, option groups and wording,
## and the planner's walk over it takes the same path through the same levels. The pieces run in
## the order the build is made of: a start, one per hostile given full analysis, a finish. And the
## confinement the snapshot carries is the one at the build's start, whatever the live one becomes
## by the time the build ends.
##
## Over two situations, nothing known (an entry) and two trespassers in plain sight (a fight, with
## the walk taking COMBAT and ENGAGE).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Walk := preload("res://tests/_ai/snapshot_walk_probe.gd")
## The build's piece kinds, as the staged build names them.
const START := 0
const HOSTILE := 1
const FINISH := 2
## What the scripted Von answers in the fight: COMBAT, then ENGAGE.
const FIGHT := [{ "pick": "combat" }, { "pick": "engage" }]
## Where the invader stands: the back garden, outside the kitchen's back door.
const NPC := Vector2(900, 190)
## Where the trespassers wait until the fight (inside, out of the NPC's sight).
const FOE_AWAY := Vector2(260, 190)
const FOE_AWAY_TOO := Vector2(260, 260)


func describe() -> Dictionary:
	return {
		"name": "A snapshot built in pieces equals the one-shot build",
		"description": "Stepped to its end, a staged build gives the facts, sections, options "
			+ "and wording sense() does, the walk over it the same path; the pieces are a start, "
			+ "one per analysed hostile and a finish; its confinement is the one at its start.",
		"tags": ["ai", "decision", "snapshot", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"npc", &"invader", NPC, { "movement:speed": 0.0, "facing": Vector2.LEFT })
	s.actor(&"foe", &"puppet", FOE_AWAY, { "faction": &"household", "max_health": 1_000_000.0 })
	s.actor(
		&"foe2", &"puppet", FOE_AWAY_TOO, { "faction": &"household", "max_health": 1_000_000.0 }
	)


func run(t: TestContext) -> void:
	await t.frames(3)
	var brain := t.controller(&"npc", &"debug_state")
	var perception: Node = brain.get("_perception")
	await _compare(t, brain, "entry", [{ "pick": "search" }], 0)
	_confinement_is_frozen(t, perception)
	# The brain acts on the scripted answers meanwhile: the fight's.
	DecisionStub.rules = FIGHT
	var npc := t.actor(&"npc")
	npc.facing = Vector2.LEFT
	t.actor(&"foe").global_position = npc.global_position + Vector2.LEFT * 40.0
	t.actor(&"foe2").global_position = npc.global_position + Vector2(-30, 28)
	var seen := func() -> bool: return (
		(brain.debug_state().get("contacts", []) as Array).filter(
			func(c): return c.get("hostile", false)
		).size() >= 2
	)
	if not t.require(await t.until(seen, 3.0), "set-up: the invader sees both trespassers"):
		return
	await _compare(t, brain, "fight", FIGHT, 2)


## One snapshot in one call and one in pieces, over the same moment: equal, as are the walks over
## them. `hostiles` is how many hostiles the NPC knows (each analysed: the cap is above two).
func _compare(
		t: TestContext, brain: Node, label: String, rules: Array, hostiles: int,
) -> void:
	var perception: Node = brain.get("_perception")
	var goal: String = brain.get("goal")
	DecisionStub.rules = rules
	var whole: Dictionary = perception.sense(goal, "digging in", 0)
	var staged = perception.begin_sense(goal, "digging in", 0)
	var kinds: Array = []
	while not staged.done():
		kinds.append(staged.next_piece())
		staged.step()
	var stepped: Dictionary = staged.result()
	var expected: Array = [START]
	for i in hostiles:
		expected.append(HOSTILE)
	expected.append(FINISH)
	t.expect_eq(kinds, expected, "%s: the pieces a build runs, in order" % label)
	t.check(not stepped.is_empty(), "%s: the build ends with a snapshot" % label)
	var walked_whole := await Walk.walk(t, brain, whole)
	var walked_stepped := await Walk.walk(t, brain, stepped)
	if t.require(
			not walked_whole.is_empty() and not walked_stepped.is_empty(),
			"%s: both walks end" % label,
	):
		t.expect_eq(walked_stepped["leaf"], walked_whole["leaf"], "%s: the walk's leaf" % label)
		t.expect_eq(
			walked_stepped["levels"], walked_whole["levels"], "%s: every level's options" % label
		)
	whole["demand"].complete()
	stepped["demand"].complete()
	for key in ["facts", "sections", "options", "sections_per_target", "gun"]:
		t.expect_eq(stepped[key], whole[key], "%s: the snapshot's %s" % [label, key])
	t.expect_eq(
		(stepped["confinement"] as RefCounted).confines(),
		(whole["confinement"] as RefCounted).confines(),
		"%s: the confinement" % label,
	)


## The confinement the snapshot carries is a copy taken as the build starts: a rule that lifts
## after the start still confines it, one that arrives after it does not, whatever the live
## confinement is when the pieces end. The brain's tick would refresh the live one anyway.
func _confinement_is_frozen(t: TestContext, perception: Node) -> void:
	var live = perception.confinement
	var goal: String = t.controller(&"npc", &"debug_state").get("goal")
	live.inside_only = true
	var lifted = perception.begin_sense(goal, "", 0)
	lifted.step()
	live.inside_only = false
	while not lifted.done():
		lifted.step()
	t.check(
		lifted.result()["confinement"].confines(),
		"a territory lifted after the build began still confines the snapshot",
	)
	var imposed = perception.begin_sense(goal, "", 0)
	imposed.step()
	live.inside_only = true
	while not imposed.done():
		imposed.step()
	live.inside_only = false
	t.check(
		not imposed.result()["confinement"].confines(),
		"a territory imposed after the build began does not reach the snapshot",
	)
