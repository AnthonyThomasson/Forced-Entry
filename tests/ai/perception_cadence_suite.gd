extends UnitSuite
## Native unit suite (pure logic): both phases of an NPC's sight cadence stay keyed on the
## perception node's own instance id, not on the part that runs them. The sight part tests a
## character it keeps in view every `SIGHT_EVERY_FRAMES` frames, phased by
## `(frame + perception.get_instance_id() + id)`, and the house part's first look for rooms and
## furniture comes `1 + perception.get_instance_id() % LEARN_EVERY_FRAMES` frames after it is asked.
## Keyed on anything else, the code still runs but every NPC looks on other frames, so
## a match plays another fight. Each case runs over several perceptions, so one whose ids happen to
## agree on the phase cannot hide a wrong key. It also pins what the cadence promises an NPC: a
## character that enters its view cone is tested at once whatever its phase, and what the NPC holds
## of one it keeps seeing is at most three frames old (`docs/gaze-and-fire.md`, #192 rule 28).

const AgentPerception := preload("res://scenes/ai/perception/agent_perception.gd")
const PerceptionSight := preload("res://scenes/ai/perception/perception_sight.gd")
const PerceptionHouse := preload("res://scenes/ai/perception/perception_house.gd")
const SightBody := preload("res://tests/_ai/sight_body.gd")
## How many perceptions each case runs over, and how many characters the sight case watches.
const COUNT := 3
## The physics frames the sight case asks about.
const FRAMES := 10


## A perception with its modules and parts built, as its controller's `_ready` leaves it.
func _perception() -> Node:
	var perception: Node = auto_free(AgentPerception.new())
	perception.setup()
	return perception


## Assert, over the first `FRAMES` physics frames, that `perception`'s sight part tests `other`,
## straight ahead of it, on the frames its phase names (`n`, `t`: which perception and character).
func _assert_due_on_phase(perception: Node, other: Node2D, n: int, t: int) -> void:
	var sight: PerceptionSight = perception.sight
	var phase := perception.get_instance_id() + other.get_instance_id()
	for frame in FRAMES:
		# The first look comes at once; after it, one on every frame of the phase.
		var want := frame == 0 or (frame + phase) % PerceptionSight.SIGHT_EVERY_FRAMES == 0
		assert_bool(sight._due_for_sight(other, Vector2.ZERO, Vector2.RIGHT, frame)) \
			.override_failure_message("perception %d, character %d, frame %d" % [n, t, frame]) \
			.is_equal(want)


func test_sight_tests_a_character_in_view_on_the_perceptions_phase() -> void:
	for n in COUNT:
		var perception := _perception()
		for t in COUNT:
			var other: Node2D = auto_free(Node2D.new())
			other.position = Vector2(100.0, 0.0)  # Straight ahead, in the view cone.
			add_child(other)
			_assert_due_on_phase(perception, other, n, t)


func test_sight_shares_one_character_list_per_world_and_frame() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var bodies: Array[Node2D] = []
	for i in COUNT:
		var body: Body = auto_free(Body.new())
		root.add_child(body)
		body.add_to_group(&"characters")
		bodies.append(body)
	var other_root: Node2D = auto_free(Node2D.new())
	add_child(other_root)
	var outsider: Body = auto_free(Body.new())
	other_root.add_child(outsider)
	outsider.add_to_group(&"characters")
	var perceptions: Array[Node] = []
	for body: Body in bodies:
		var perception := _perception()
		perceptions.append(perception)
		perception.set("_character", body)
		var expected := bodies.filter(func(candidate: Node2D) -> bool: return candidate != body)
		assert_array(perception.sight.others()).is_equal(expected)
	var builds := 0
	for perception: Node in perceptions:
		var count: Variant = perception.sight.get("list_builds")
		if count != null:
			builds += int(count)
	assert_int(builds).is_equal(1)


func test_house_intake_repeats_only_changed_setup() -> void:
	var perception := _perception()
	var tuning: NpcTuning = auto_free(NpcTuning.defaults())
	perception.apply_config(tuning)
	var body: HouseBody = auto_free(HouseBody.new())
	add_child(body)
	perception.set("_character", body)
	perception.grenades.throw.bind(body)
	perception.tuning.entry.enabled = false
	var openings: Array = []
	var rooms: Array = [{ "key": &"room", "type": &"living", "rect": Rect2(0, 0, 200, 200) }]
	perception.house.openings = openings
	perception.house.take_in(rooms)
	perception.house.take_in(rooms)
	assert_int(_intake_reads(perception, &"house")).is_equal(1)
	assert_int(_intake_reads(perception, &"carried")).is_equal(1)
	assert_int(_intake_reads(perception, &"body")).is_equal(1)
	rooms = rooms.duplicate()
	perception.house.take_in(rooms)
	assert_int(_intake_reads(perception, &"house")).is_equal(2)
	assert_int(_intake_reads(perception, &"carried")).is_equal(1)
	assert_int(_intake_reads(perception, &"body")).is_equal(1)
	body.inventory.item = RefCounted.new()
	perception.house.take_in(rooms)
	assert_int(_intake_reads(perception, &"house")).is_equal(2)
	assert_int(_intake_reads(perception, &"carried")).is_equal(2)
	assert_int(_intake_reads(perception, &"body")).is_equal(1)


func _intake_reads(perception: Node, key: StringName) -> int:
	var reads: Variant = perception.house.get("intake_reads")
	return int(reads.get(key, -1)) if reads is Dictionary else -1


func test_house_looks_first_on_the_perceptions_phase() -> void:
	for n in COUNT:
		var perception := _perception()
		var body: Body = auto_free(Body.new())
		add_child(body)
		perception.set("_character", body)
		var frame := Engine.get_physics_frames()
		perception.house.learn_by_sight()
		assert_int(perception.house.learn_next) \
			.override_failure_message("perception %d" % n) \
			.is_equal(
				frame + 1 + perception.get_instance_id() % PerceptionHouse.LEARN_EVERY_FRAMES
			)


func test_sight_sees_the_cone_and_the_bubble_and_a_character_entering_the_cone_at_once() -> void:
	var watcher := _watcher()
	var sight: PerceptionSight = watcher["perception"].sight
	var seen: Dictionary = watcher["others"]
	await get_tree().physics_frame
	sight.see([])
	assert_array(_sorted(sight.visible_now.keys())).is_equal(_sorted([
		seen["ahead"].get_instance_id(),
		seen["bubble"].get_instance_id(),
	]))
	# A character out of the cone is first tested on the frame it enters it, however its phase
	# falls: wait for a frame that is off its phase, then turn it into the cone.
	var entering: Node2D = seen["side"]
	var pid: int = watcher["perception"].get_instance_id()
	while (Engine.get_physics_frames() + pid + entering.get_instance_id()) \
			% PerceptionSight.SIGHT_EVERY_FRAMES == 0:
		await get_tree().physics_frame
	entering.position = Vector2(200.0, 40.0)
	sight.see([])
	assert_bool(sight.visible_now.has(entering.get_instance_id())) \
		.override_failure_message("a character entering the cone is tested at once") \
		.is_true()
	# And one that leaves it is dropped at once.
	entering.position = Vector2(0.0, 300.0)
	await get_tree().physics_frame
	sight.see([])
	assert_bool(sight.visible_now.has(entering.get_instance_id())).is_false()


func test_sight_holds_a_character_it_keeps_seeing_at_most_three_frames_old() -> void:
	var watcher := _watcher()
	var sight: PerceptionSight = watcher["perception"].sight
	var mover: Node2D = watcher["others"]["ahead"]
	var step := 10.0
	for frame in 12:
		await get_tree().physics_frame
		mover.position.x += step
		sight.see([])
		var held: Vector2 = watcher["perception"]._memory.recall_all(&"saw_character") \
			.filter(func(d): return d["id"] == mover.get_instance_id())[0]["pos"]
		var frames_old := (mover.position.x - held.x) / step
		assert_float(frames_old) \
			.override_failure_message("frame %d: held %d frames old" % [frame, int(frames_old)]) \
			.is_between(0.0, 3.0)


func test_sight_pass_builds_no_per_npc_character_list() -> void:
	var first := _watcher()
	var second := _watcher(first["root"])
	await get_tree().physics_frame
	for watcher: Dictionary in [first, second]:
		watcher["perception"].sight.see([])
	var calls := 0
	for watcher: Dictionary in [first, second]:
		var n: Variant = watcher["perception"].sight.get("others_calls")
		calls += int(n) if n != null else -1000
	assert_int(calls).is_equal(0)
	# Both saw what is in their cones all the same.
	var ahead: Node2D = first["others"]["ahead"]
	assert_bool(first["perception"].sight.visible_now.has(ahead.get_instance_id())).is_true()


func test_house_looks_for_a_third_of_the_unknown_furniture_each_time() -> void:
	var body: SightBody = auto_free(SightBody.new())
	var perception := _perception()
	perception.apply_config(auto_free(NpcTuning.defaults()))
	add_child(body)
	perception.set("_character", body)
	var pieces := _furniture(6)
	perception.house.interactables = pieces
	var learned: Array[int] = []
	for look in 3:
		await get_tree().physics_frame
		perception.house.learn_by_sight()
		learned.append(perception.house.known_object_ids().size())
	# A look takes at most a third of the pieces (rounded up), and three looks cover them all, so a
	# piece in view is learned at most three looks (18 frames) after it comes into view.
	assert_int(learned[0]).is_between(1, 2)
	assert_int(learned[1] - learned[0]).is_between(1, 2)
	assert_int(learned[2]).is_equal(6)


func test_a_decisions_look_for_furniture_is_a_full_look() -> void:
	var body: SightBody = auto_free(SightBody.new())
	var perception := _perception()
	perception.apply_config(auto_free(NpcTuning.defaults()))
	add_child(body)
	perception.set("_character", body)
	perception.house.interactables = _furniture(6)
	await get_tree().physics_frame
	perception.house.learn_by_sight()
	assert_int(perception.house.known_object_ids().size()).is_less(6)
	# The decision's own look, in the same frame as the scheduled one, covers every piece in view.
	perception.house.learn_by_sight(true)
	assert_int(perception.house.known_object_ids().size()).is_equal(6)


## `count` pieces in the cone of a body at the origin facing +x, in the clear, each a distinct spot.
func _furniture(count: int) -> Array:
	var out: Array = []
	for i in count:
		var piece: Node2D = auto_free(Node2D.new())
		add_child(piece)
		piece.position = Vector2(150.0 + 30.0 * i, 20.0 * i - 50.0)
		out.append(piece)
	return out


## `ids` sorted, for an order-free comparison.
func _sorted(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort()
	return out


## A watching NPC at the origin facing +x with its perception, and the characters around it: one
## `ahead` in the cone, one at the `side` and one `behind` (out of the cone), one `bubble` close
## behind it (inside the near bubble), one `dead` ahead. They share `root` (a new one by default).
func _watcher(root: Node2D = null) -> Dictionary:
	if root == null:
		root = auto_free(Node2D.new())
		add_child(root)
	var perception := _perception()
	perception.apply_config(auto_free(NpcTuning.defaults()))
	var body: SightBody = auto_free(SightBody.new())
	root.add_child(body)
	body.add_to_group(&"characters")
	perception.set("_character", body)
	var others := {}
	for entry in [
		["ahead", Vector2(200.0, 0.0)],
		["side", Vector2(0.0, 300.0)],
		["behind", Vector2(-300.0, 0.0)],
		["bubble", Vector2(-30.0, 0.0)],
		["dead", Vector2(300.0, 0.0)],
	]:
		var other: SightBody = auto_free(SightBody.new())
		other.faction = &"invader"
		other.is_dead = entry[0] == "dead"
		root.add_child(other)
		other.position = entry[1]
		other.add_to_group(&"characters")
		others[entry[0]] = other
	return { "root": root, "perception": perception, "body": body, "others": others }


## A body as the house part's look reads it: where it stands, its facing, its world and its rid.
class Body:
	extends CharacterBody2D

	var facing := Vector2.RIGHT

	## The world this body's sight list is scoped to.
	func world_root() -> Node:
		return get_parent()


## A body with the inventory and posture surfaces house intake reads.
class HouseBody:
	extends Body

	var inventory := HouseInventory.new()
	var movement := HouseMovement.new()


## Two grenade slots whose item identity a test can replace.
class HouseInventory:
	extends RefCounted

	var item: RefCounted = RefCounted.new()

	func item_in(_slot: int) -> RefCounted:
		return item

	func throw_stats(slot: int) -> Dictionary:
		return { "kind": &"stun" } if item_in(slot) != null else {}

	func throw_release_offset(_slot: int) -> Vector2:
		return Vector2(12, 3)


## Fixed standing and crouching heights.
class HouseMovement:
	extends RefCounted

	func posture_coverage(which: StringName) -> float:
		return 35.0 if which == &"crouch" else 100.0
