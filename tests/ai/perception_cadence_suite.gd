extends UnitSuite
## Native unit suite (pure logic): the sight cadence stays keyed on spawn order (`WorldRng`), not on
## the part that runs it or on an instance id, and the house intake repeats only changed setup. The
## sight case tests a character it keeps in view every `SIGHT_EVERY_FRAMES` frames, phased by
## `(frame + the NPC's spawn order + the target's)`, over several NPCs, so one whose orders happen
## to agree on the phase cannot hide a wrong key. What needs a world and physics frames (the shared
## character list, a character entering the cone, the held age, the house looks' phases and their
## reach) is `ai/perception/sight_cadence` and `ai/perception/house_look_cadence`.

const AgentPerception := preload("res://scenes/ai/perception/agent_perception.gd")
const PerceptionSight := preload("res://scenes/ai/perception/perception_sight.gd")
## How many perceptions the sight case runs over, and how many characters each watches.
const COUNT := 3
## The physics frames the sight case asks about.
const FRAMES := 10


## A perception with its modules and parts built, as its controller's `_ready` leaves it.
func _perception() -> Node:
	var perception: Node = auto_free(AgentPerception.new())
	perception.setup()
	return perception


## Assert, over the first `FRAMES` physics frames, that `sight` tests `other`, straight ahead of its
## NPC, on the frames its phase names: `phase`, the spawn orders of the NPC and of `other` added
## (`n`, `t`: which NPC and character).
func _assert_due_on_phase(
	sight: PerceptionSight,
	other: Node2D,
	phase: int,
	n: int,
	t: int,
) -> void:
	for frame in FRAMES:
		# The first look comes at once; after it, one on every frame of the phase.
		var want := frame == 0 or (frame + phase) % PerceptionSight.SIGHT_EVERY_FRAMES == 0
		assert_bool(sight._due_for_sight(other, Vector2.ZERO, Vector2.RIGHT, frame)) \
			.override_failure_message("perception %d, character %d, frame %d" % [n, t, frame]) \
			.is_equal(want)


func test_sight_tests_a_character_in_view_on_its_spawn_order_phase() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	WorldRng.register(root, 0)
	var spawned := 0  # The spawn order the next node takes: counted here, from the spec.
	for n in COUNT:
		var perception := _perception()
		var body: Node2D = auto_free(Node2D.new())
		root.add_child(body)
		WorldRng.enrol(body)
		perception.set("_character", body)
		var mine := spawned
		spawned += 1
		for t in COUNT:
			var other: Node2D = auto_free(Node2D.new())
			other.position = Vector2(100.0, 0.0)  # Straight ahead, in the view cone.
			root.add_child(other)
			WorldRng.enrol(other)
			_assert_due_on_phase(perception.sight, other, mine + spawned, n, t)
			spawned += 1


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
