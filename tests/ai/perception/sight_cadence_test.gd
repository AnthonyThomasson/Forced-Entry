extends GameTest
## The sight cadence of an NPC's perception (`perception_sight.gd`) in a world over physics frames:
## it shares one character list per world and frame, sees the cone and the bubble, tests a
## character entering its view cone at once whatever its phase and drops one leaving it at once,
## holds a character it keeps seeing at most three frames old (`SIGHT_EVERY_FRAMES`), and builds no
## per-NPC character list in its pass.

const Probe := preload("res://tests/_ai/cadence_probe.gd")
const SightBody := preload("res://tests/_ai/sight_body_probe.gd")
const PerceptionSight := preload("res://scenes/ai/perception/perception_sight.gd")
## Characters sharing a world in the list case.
const COUNT := 3
## Frames the held-age case watches, and how far the mover steps each.
const AGE_FRAMES := 12
const STEP := 10.0

var _made: Array[Node] = []


func describe() -> Dictionary:
	return {
		"name": "A perception's sight cadence holds over frames in a world",
		"description": "One character list per world and frame; the cone and bubble seen; a "
			+ "character entering the cone tested at once and one leaving dropped at once; what "
			+ "is held of a seen character at most three frames old; no per-NPC list built.",
		"tags": ["ai", "perception", "sight"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"lighting.enabled", false)


func run(t: TestContext) -> void:
	_shares_one_list_per_world(t)
	await t.frames(1)
	await _cone_bubble_and_entering(t)
	await _holds_at_most_three_frames_old(t)
	await _builds_no_per_npc_list(t)
	for node in _made:
		node.free()


func _shares_one_list_per_world(t: TestContext) -> void:
	var root := Node2D.new()
	t.world.add_child(root)
	var bodies: Array[Node2D] = []
	for i in COUNT:
		var body := SightBody.new()
		root.add_child(body)
		body.add_to_group(&"characters")
		bodies.append(body)
	var other_root := Node2D.new()
	t.world.add_child(other_root)
	var outsider := SightBody.new()
	other_root.add_child(outsider)
	outsider.add_to_group(&"characters")
	var perceptions: Array[Node] = []
	for body: Node2D in bodies:
		var perception := Probe.perception()
		_made.append(perception)
		perceptions.append(perception)
		perception.set("_character", body)
		var expected := bodies.filter(func(candidate: Node2D) -> bool: return candidate != body)
		t.expect_eq(
			perception.sight.others(), expected, "a perception lists the others of its world only"
		)
	var builds := 0
	for perception: Node in perceptions:
		var count: Variant = perception.sight.get("list_builds")
		if count != null:
			builds += int(count)
	t.expect_eq(builds, 1, "the character list is built once for the world and frame")


func _cone_bubble_and_entering(t: TestContext) -> void:
	var watcher := Probe.watcher(_root(t))
	_made.append(watcher["perception"])
	var sight: PerceptionSight = watcher["perception"].sight
	var seen: Dictionary = watcher["others"]
	await t.frames(1)
	sight.see([])
	t.expect_eq(
		Probe.sorted(sight.visible_now.keys()),
		Probe.sorted([seen["ahead"].get_instance_id(), seen["bubble"].get_instance_id()]),
		"the cone and the bubble are seen",
	)
	# A character out of the cone is first tested on the frame it enters it, however its phase
	# falls: wait for a frame that is off its phase, then turn it into the cone.
	var entering: Node2D = seen["side"]
	var mine := WorldRng.order_of(watcher["body"].get_instance_id())
	var theirs := WorldRng.order_of(entering.get_instance_id())
	while (WorldRng.frame_of(watcher["body"]) + mine + theirs) \
			% PerceptionSight.SIGHT_EVERY_FRAMES == 0:
		await t.frames(1)
	entering.position = Vector2(200.0, 40.0)
	sight.see([])
	t.check(
		sight.visible_now.has(entering.get_instance_id()),
		"a character entering the cone is tested at once",
	)
	# And one that leaves it is dropped at once.
	entering.position = Vector2(0.0, 300.0)
	await t.frames(1)
	sight.see([])
	t.check(
		not sight.visible_now.has(entering.get_instance_id()),
		"a character leaving the cone is dropped at once",
	)


func _holds_at_most_three_frames_old(t: TestContext) -> void:
	var watcher := Probe.watcher(_root(t))
	_made.append(watcher["perception"])
	var sight: PerceptionSight = watcher["perception"].sight
	var mover: Node2D = watcher["others"]["ahead"]
	for frame in AGE_FRAMES:
		await t.frames(1)
		mover.position.x += STEP
		sight.see([])
		var held: Vector2 = watcher["perception"]._memory.recall_all(&"saw_character") \
			.filter(func(d): return d["id"] == mover.get_instance_id())[0]["pos"]
		var frames_old := (mover.position.x - held.x) / STEP
		t.check(
			frames_old >= 0.0 and frames_old <= 3.0,
			"frame %d: held %d frames old" % [frame, int(frames_old)],
		)


func _builds_no_per_npc_list(t: TestContext) -> void:
	var shared := _root(t)
	var first := Probe.watcher(shared)
	var second := Probe.watcher(shared)
	_made.append(first["perception"])
	_made.append(second["perception"])
	await t.frames(1)
	for watcher: Dictionary in [first, second]:
		watcher["perception"].sight.see([])
	var calls := 0
	for watcher: Dictionary in [first, second]:
		var n: Variant = watcher["perception"].sight.get("others_calls")
		calls += int(n) if n != null else -1000
	t.expect_eq(calls, 0, "a sight pass builds no per-NPC character list")
	var ahead: Node2D = first["others"]["ahead"]
	t.check(
		first["perception"].sight.visible_now.has(ahead.get_instance_id()),
		"both saw what is in their cones all the same",
	)


## A new root in the world for one case's characters.
func _root(t: TestContext) -> Node2D:
	var root := Node2D.new()
	t.world.add_child(root)
	return root
