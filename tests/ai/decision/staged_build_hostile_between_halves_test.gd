extends GameTest
## A hostile's analysis is two pieces (`AgentSnapshot._analyse_step`) and both read the hostile
## through one pinned copy: its eye and its twin rid taken once, in the first. So a hostile that
## ducks between the two pieces is analysed at the posture the first saw (the snapshot is the one a
## standing hostile gives), and one that is freed between them (shot dead and gone, a despawn) is
## left out of the second half's rays: the build ends, nothing casts a freed node.

const NPC := Vector2(150, 250)
const SPOTS := [Vector2(500, 100), Vector2(600, 300)]
const HOSTILE := 1


func describe() -> Dictionary:
	return {
		"name": "A hostile that ducks or is freed between its two analysis pieces",
		"description": "A staged build stopped after the first half of a hostile's analysis: "
			+ "the hostile ducks and the snapshot is the one a standing hostile gives; a hostile "
			+ "freed there leaves the build ending with no error and the others analysed.",
		"tags": ["ai", "decision", "snapshot", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.actor(&"d", &"defender", NPC, { "movement:speed": 0.0, "facing": Vector2.RIGHT })
	for i in SPOTS.size():
		s.actor(
			StringName("h%d" % i), &"puppet", SPOTS[i],
			{ "faction": &"invader", "max_health": 1_000_000.0 },
		)


func run(t: TestContext) -> void:
	var brain := t.controller(&"d", &"debug_state")
	var seen := func() -> bool: return (
		(brain.debug_state().get("contacts", []) as Array).filter(
			func(c): return c.get("hostile", false)
		).size() == SPOTS.size()
	)
	if not t.require(await t.until(seen, 3.0), "set-up: the defender sees both hostiles"):
		return
	var perception: Node = brain.get("_perception")
	var goal: String = brain.get("goal")
	_ducked(t, perception, goal)
	t.puppet(&"h0").set_posture(&"stand")
	await t.frames(1)
	_freed(t, perception, goal)


## Ducked between the halves of the first hostile's analysis: the snapshot a standing one gives.
func _ducked(t: TestContext, perception: Node, goal: String) -> void:
	var standing: Dictionary = perception.sense(goal, "", 0)
	var staged = perception.begin_sense(goal, "", 0)
	_step_to_between_halves(t, staged)
	t.puppet(&"h0").set_posture(&"crouch")
	while not staged.done():
		staged.step()
	var ducked: Dictionary = staged.result()
	t.expect_eq(ducked["options"], standing["options"], "ducked between halves: the options")
	t.expect_eq(
		ducked["sections_per_target"], standing["sections_per_target"], "... and the sections"
	)


## Freed between the halves: the build ends and the hostile is analysed from what the first saw.
func _freed(t: TestContext, perception: Node, goal: String) -> void:
	var staged = perception.begin_sense(goal, "", 0)
	_step_to_between_halves(t, staged)
	var first: Node = t.actor(&"h0")
	var id := first.get_instance_id()
	first.free()
	var pieces := 0
	while not staged.done() and pieces < 20:
		staged.step()
		pieces += 1
	t.check(staged.done(), "freed between halves: the build ends (%d more pieces)" % pieces)
	var analysed: Array = (staged.result()["sections_per_target"] as Dictionary).keys()
	t.check(analysed.has(id), "... the hostile still analysed (%s of %s)" % [id, analysed])


## Steps a build to just after the first half of its first hostile's analysis.
func _step_to_between_halves(t: TestContext, staged: RefCounted) -> void:
	staged.step()
	t.expect_eq(staged.next_piece(), HOSTILE, "set-up: the START ran, a hostile piece is next")
	staged.step()
	t.expect_eq(staged.next_piece(), HOSTILE, "set-up: the hostile's second half is next")
