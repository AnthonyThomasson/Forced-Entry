extends GameTest
## A staged build reads the damage the NPC has taken once, in its START (`AgentSnapshot`,
## `parts["dmg"]`), and the RETREAT piece, the finish's `hurt` fact and the situation line all use
## it: an NPC shot between two pieces of its own build is described as it was when the build began,
## as a build
## made whole (`sense()`) at that moment describes it. Under fire with no hostile known, where the
## retreat spots are still worked out ahead of the finish.

const NPC := Vector2(150, 250)
const Piece := preload("res://scenes/ai/perception/snapshot/snapshot_build.gd").Piece
## More than the `hurt_threshold` (15) of damage.
const HURT := 60.0


func describe() -> Dictionary:
	return {
		"name": "A staged build reads the damage taken once, as it begins",
		"description": "Under fire with no hostile known, an NPC hurt after its build's start but "
			+ "before the retreat piece gets the snapshot of the NPC unhurt: the retreat "
			+ "summary, the hurt fact and the situation line all say what the start read.",
		"tags": ["ai", "decision", "snapshot", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.actor(&"d", &"defender", NPC, { "movement:speed": 0.0, "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	await t.frames(3)
	var brain := t.controller(&"d", &"debug_state")
	var perception: Node = brain.get("_perception")
	var goal: String = brain.get("goal")
	var body: Node = t.actor(&"d")
	var deformable: Object = body.anatomy.deformable
	if not t.require(deformable != null, "set-up: the defender's body keeps damage"):
		return
	perception.get("_memory").remember(&"under_fire", { "from": Vector2(700, 250) }, 30.0)
	t.require(perception.under_fire(), "set-up: the defender is under fire")
	var unhurt: Dictionary = perception.sense(goal, "", 0)
	var staged = perception.begin_sense(goal, "", 0)
	var kinds: Array = []
	staged.step()
	deformable.damage_total = HURT  # shot after its START, before its retreat piece
	while not staged.done():
		kinds.append(staged.next_piece())
		staged.step()
	deformable.damage_total = 0.0
	t.check(kinds.has(Piece.RETREAT), "set-up: under fire the build runs a RETREAT piece")
	var stepped: Dictionary = staged.result()
	unhurt["demand"].complete()
	stepped["demand"].complete()
	for key in ["facts", "sections", "options"]:
		t.expect_eq(stepped[key], unhurt[key], "hurt after the start: the snapshot's %s" % key)
