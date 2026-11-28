extends GameTest
## The nav updater's ticks keep one place relative to the world's staging whichever point of a
## frame the stage was begun at (#194). A fight's re-baked navmesh landed a frame earlier or later
## by it: a live Von run builds its world from the launcher's own `_process`, a replay from a
## physics step's signal, a second run of a test from whatever gdUnit resumed it in, and the same
## fight then planned its walks on a different mesh, so a recording did not replay (the nav
## updater's interval timer kept or lost its first frame by where it was added).
## `MatchBuilder.stage` is begun in four places: the process frame's signal, a node's process pass,
## a physics step's signal and a node's physics pass. In each, the updater's first ticks fall the
## same number of physics frames after the stage returns (the frame the world's actors are placed
## on).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SEED := 18
const ENTRANCE := Vector2(440, 350)
## The ticks read of each updater.
const TICKS := 2
## Where the stage is begun.
const PROCESS_SIGNAL := &"process frame signal"
const PROCESS_PASS := &"process pass"
const PHYSICS_SIGNAL := &"physics frame signal"
const PHYSICS_PASS := &"physics pass"


func describe() -> Dictionary:
	return {
		"name": "The nav updater ticks the same after the stage whichever phase it began in",
		"description": "A world staged from the process frame's signal, a node's process pass, a "
			+ "physics step's signal and a node's physics pass: its updater's first ticks come "
			+ "the same number of physics frames after the stage returns.",
		"tags": ["navigation", "rebake", "determinism"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 300, 300))


func run(t: TestContext) -> void:
	var after := {}
	for place: StringName in [PROCESS_SIGNAL, PROCESS_PASS, PHYSICS_SIGNAL, PHYSICS_PASS]:
		var stager := await _stage_from(t, place)
		if not t.require(stager != null, "the updater of the stage from the %s ticked" % place):
			return
		after[place] = stager.ticks.slice(0, TICKS).map(
			func(tick: int) -> int: return tick - stager.returned
		)
		await MainProbe.close(t, stager.world.get_parent())
	for place: StringName in after:
		t.expect_eq(
			after[place] as Array,
			after[PROCESS_SIGNAL] as Array,
			"frames from the stage's return to the ticks, begun from the %s" % place,
		)


## Stage a world begun at `place` and wait for `TICKS` ticks of its updater; null when they never
## came.
func _stage_from(t: TestContext, place: StringName) -> Stager:
	var stager := Stager.new()
	stager.spec = MatchBuilder.spec({ "seed": SEED, "entrance": ENTRANCE, "wait_nav": true })
	t.world.add_child(stager)
	var viewport := MainProbe.viewport(t)
	stager.world = Node2D.new()
	stager.world.name = "World"
	viewport.add_child(stager.world)
	var tree := t.world.get_tree()
	match place:
		PROCESS_SIGNAL:
			tree.process_frame.connect(stager.begin, CONNECT_ONE_SHOT)
		PHYSICS_SIGNAL:
			tree.physics_frame.connect(stager.begin, CONNECT_ONE_SHOT)
		PROCESS_PASS:
			stager.in_my_pass(&"process")
		PHYSICS_PASS:
			stager.in_my_pass(&"physics")
	var ticked := await t.until(func() -> bool: return stager.ticks.size() >= TICKS, 20.0)
	return stager if ticked else null


## A stage begun from a place of the caller's choosing, and what came of it.
class Stager:
	extends Node


	var spec: Dictionary


	var world: Node2D


	## The physics frame the stage returned on, and the ones the re-baker ticked on.
	var returned := -1


	var ticks: Array[int] = []


	var _pass := &""


	func _ready() -> void:
		set_process(false)
		set_physics_process(false)


	func _process(_delta: float) -> void:
		set_process(false)
		await begin()


	func _physics_process(_delta: float) -> void:
		set_physics_process(false)
		await begin()


	## Begin the stage from the next process or physics pass of this node.
	func in_my_pass(pass_name: StringName) -> void:
		_pass = pass_name
		set_process(pass_name == &"process")
		set_physics_process(pass_name == &"physics")


	## Stage the world, then count the re-baker's ticks.
	func begin() -> void:
		await MatchBuilder.stage(spec, world)
		returned = Engine.get_physics_frames()
		var timer := world.get_node("NavUpdater/RebakeTimer") as Timer
		timer.timeout.connect(func() -> void: ticks.append(Engine.get_physics_frames()))
