extends GameTest
## A hostile's analysis is a run of pieces (`AgentSnapshot._analyse_step`: rings, spots, a flank a
## side, the rest) and all read the hostile through one pinned copy: its eye and its twin rid taken
## once, in the first. So a hostile that ducks between two of its pieces is analysed at the posture
## the first saw (the snapshot is the one a standing hostile gives), and one that is freed between
## them (shot dead and gone, a despawn) is left out of the later rays: the build ends, nothing
## casts a freed node. Tried before each of the pieces after the first.

const NPC := Vector2(150, 250)
const SPOTS := [Vector2(500, 100), Vector2(600, 300)]
const Piece := preload("res://scenes/ai/perception/snapshot/snapshot_build.gd").Piece
## The pieces of a hostile's analysis after its first: the build is stopped before each.
const LATER := [Piece.SPOTS, Piece.FLANKS, Piece.REST]


func describe() -> Dictionary:
	return {
		"name": "A hostile that ducks or is freed between its analysis pieces",
		"description": "A staged build stopped between the pieces of a hostile's analysis: "
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
	for before: int in LATER:
		_ducked(t, perception, goal, before)
		t.puppet(&"h0").set_posture(&"stand")
		await t.frames(1)
	_freed(t, perception, goal, LATER[0])  # Once: the hostile is gone.


## Ducked between two pieces of the first hostile's analysis: the snapshot a standing one gives.
func _ducked(t: TestContext, perception: Node, goal: String, before: int) -> void:
	var standing: Dictionary = perception.sense(goal, "", 0)
	var staged = perception.begin_sense(goal, "", 0)
	_step_to_before(t, staged, before)
	t.puppet(&"h0").set_posture(&"crouch")
	while not staged.done():
		staged.step()
	var ducked: Dictionary = staged.result()
	t.expect_eq(
		ducked["options"],
		standing["options"],
		"ducked before piece %d: the options" % before,
	)
	t.expect_eq(
		ducked["sections_per_target"], standing["sections_per_target"], "... and the sections"
	)


## Freed between two pieces: the build ends and the hostile is analysed from what the first saw.
func _freed(t: TestContext, perception: Node, goal: String, before: int) -> void:
	var staged = perception.begin_sense(goal, "", 0)
	_step_to_before(t, staged, before)
	var first: Node = t.actor(&"h0")
	var id := first.get_instance_id()
	first.free()
	var pieces := 0
	while not staged.done() and pieces < 20:
		staged.step()
		pieces += 1
	t.check(
		staged.done(),
		"freed before piece %d: the build ends (%d more pieces)" % [before, pieces],
	)
	var analysed: Array = (staged.result()["sections_per_target"] as Dictionary).keys()
	t.check(analysed.has(id), "... the hostile still analysed (%s of %s)" % [id, analysed])


## Steps a build to just before the piece of kind `before` of its first hostile's analysis.
func _step_to_before(t: TestContext, staged: RefCounted, before: int) -> void:
	staged.step()
	t.expect_eq(
		staged.next_piece(),
		Piece.HOSTILE,
		"set-up: the START ran, a hostile piece is next",
	)
	var pieces := 0
	while staged.next_piece() != before and pieces < 20:
		staged.step()
		pieces += 1
	t.expect_eq(staged.next_piece(), before, "set-up: stopped before piece %d" % before)
