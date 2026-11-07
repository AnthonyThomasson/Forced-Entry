extends GameTest
## A group the snapshot builds on demand reads memory, physics and navigation as they are when the
## walk first asks for it, up to a walk's latency after the decision began (rule 23): a gunshot
## heard and a door turned between the snapshot's build and the walk. The walk over that snapshot
## does not throw (an error fails the test), loses no option, and offers what a snapshot built
## after the change offers; a snapshot completed before the change does not offer the heard lead,
## so the lazy one did read it live.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Walk := preload("res://tests/_ai/snapshot_walk_probe.gd")
## Where the invader stands: the back garden, outside the kitchen's back door.
const NPC := Vector2(900, 190)
## A door turned this many degrees.
const TURN := 60.0
const DOOR := {
	"name": "back", "material": "hollow", "style": "flush",
	"hinge": Vector2(840, 166), "swing_into": Vector2.LEFT,
}


func describe() -> Dictionary:
	return {
		"name": "Option groups built on demand read the world as the walk finds it",
		"description": "A gunshot heard and a door turned after a snapshot is built: the walk "
			+ "that then reads its lazy groups loses no option, and sees what a snapshot built "
			+ "after the change sees.",
		"tags": ["ai", "decision", "snapshot", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false, DOOR)
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"npc", &"invader", NPC, { "movement:speed": 0.0, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	await t.frames(3)
	var brain := t.controller(&"npc", &"debug_state")
	var perception: Node = brain.get("_perception")
	var door := t.world.get_tree().get_first_node_in_group(&"doors")
	if not t.require(door != null and door.angle() == 0.0, "set-up: a shut door stands"):
		return
	var goal: String = brain.get("goal")
	DecisionStub.rules = [{ "pick": "investigate" }]
	var lazy_snap: Dictionary = perception.sense(goal, "", 0)
	var before: Dictionary = perception.sense(goal, "", 0)
	before["demand"].complete()
	t.require(
		(lazy_snap["demand"].built as Array).is_empty(),
		"premise: nothing is built before the world changes",
	)
	await _change_world(t, lazy_snap, door)
	var after: Dictionary = perception.sense(goal, "", 0)
	after["demand"].complete()
	var walked := await Walk.walk(t, brain, lazy_snap)
	var fresh := await Walk.walk(t, brain, after)
	if not t.require(not walked.is_empty() and not fresh.is_empty(), "both walks end"):
		return
	t.check(
		(lazy_snap["demand"].built as Array).has("leads"),
		"the walk read the leads (%s)" % str(lazy_snap["demand"].built),
	)
	lazy_snap["demand"].complete()
	var leads: Variant = lazy_snap["options"].get("leads", {})
	t.check(not leads.is_empty(), "the walk lost no lead option")
	t.check(
		leads != before["options"].get("leads", {}),
		"the lazy leads are not those a snapshot completed before the shot holds (premise)",
	)
	t.expect_eq(walked["leaf"], fresh["leaf"], "the walk ends where one over a fresh snapshot does")
	# The state text is the decision's frozen copy (it does not hold the shot); the groups are live.
	t.expect_eq(_offers(walked), _offers(fresh), "every level's options and their text")
	t.expect_eq(lazy_snap["options"], after["options"], "the full option set")


## What each level of `walk` offered, and what it picked.
func _offers(walk: Dictionary) -> Array:
	return (walk["levels"] as Array).map(
		func(level: Dictionary) -> Dictionary:
			return { "node": level["node"], "offered": level["offered"], "pick": level["pick"] }
	)


## A gunshot heard in the kitchen and the door turned, with the lazy snapshot still unread.
func _change_world(t: TestContext, lazy_snap: Dictionary, door: Node) -> void:
	EventBus.post(
		&"hit",
		{
			"position": Maps.KITCHEN_CENTRE, "direction": Vector2.LEFT, "damage": 10.0,
			"attacker": null, "victim": null,
		},
	)
	door.turn_by(TURN, null)
	await t.seconds(1.0)
	t.require(door.angle() > 0.0, "premise: the door has turned (%s)" % door.angle())
	t.require(
		(lazy_snap["demand"].built as Array).is_empty(),
		"premise: the walk has not read a lazy group yet",
	)
