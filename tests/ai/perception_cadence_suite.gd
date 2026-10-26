extends UnitSuite
## Native unit suite (pure logic): both phases of an NPC's sight cadence stay keyed on the
## perception node's own instance id, not on the part that runs them. The sight part tests a
## character it keeps in view every `SIGHT_EVERY_FRAMES` frames, phased by
## `(frame + perception.get_instance_id() + id)`, and the house part's first look for rooms and
## furniture comes `1 + perception.get_instance_id() % LEARN_EVERY_FRAMES` frames after it is asked.
## Keyed on anything else, the code still runs but every NPC looks on other frames than before, so
## a match plays another fight. Each case runs over several perceptions, so one whose ids happen to
## agree on the phase cannot hide a wrong key.

const AgentPerception := preload("res://scenes/ai/perception/agent_perception.gd")
const PerceptionSight := preload("res://scenes/ai/perception/perception_sight.gd")
const PerceptionHouse := preload("res://scenes/ai/perception/perception_house.gd")
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


func test_house_looks_first_on_the_perceptions_phase() -> void:
	for n in COUNT:
		var perception := _perception()
		var body: Body = auto_free(Body.new())
		add_child(body)
		perception.set("_character", body)
		var frame := Engine.get_physics_frames()
		perception.house.learn_by_sight([])
		assert_int(perception.house.learn_next) \
			.override_failure_message("perception %d" % n) \
			.is_equal(
				frame + 1 + perception.get_instance_id() % PerceptionHouse.LEARN_EVERY_FRAMES
			)


## A body as the house part's look reads it: where it stands, its facing, its world and its rid.
class Body:
	extends CharacterBody2D

	var facing := Vector2.RIGHT
