extends UnitSuite
## Native unit suite (pure logic): `Behavior.gait.needs_every_frame` (`behavior_gait.gd`, the beat's
## wake list in `beat.md`), one clause at a time against a stand-in behaviour: every part at rest
## leaves the NPC on its beat, and each clause set alone wakes it. Dropping any one clause from the
## function fails the case that sets only it.

const Gait := preload("res://scenes/ai/behavior/behavior_gait.gd")
const RunningLeaf := preload("res://scenes/ai/behavior/running_leaf.gd")
const DOORWAY := Vector2(500, 300)


## A gait on a resting behaviour: no leaf, the NPC far from the doorway.
func _rest() -> Array:
	var behavior: FakeBehavior = auto_free(FakeBehavior.new())
	auto_free(behavior._character)
	behavior._character.global_position = DOORWAY + Vector2(1000, 0)
	return [Gait.new(behavior), behavior]


## Whether the gait of a behaviour `setup` has changed needs every frame.
func _wakes(setup: Callable) -> bool:
	var rest := _rest()
	setup.call(rest[1])
	return rest[0].needs_every_frame()


func test_at_rest_it_stays_on_its_beat() -> void:
	assert_bool(_wakes(func(_b): pass)).is_false()
	assert_bool(_wakes(func(b): b.task.primitive = &"entry")) \
		.override_failure_message("an entry approach 1000 px from its doorway coasts") \
		.is_false()


func test_a_committed_npc_wakes_it_even_on_an_entry_approach_far_off() -> void:
	# The bang's thrower walks out to its throw spot in the approach phase: committed, not close.
	assert_bool(_wakes(func(b):
		b.task.primitive = &"entry"
		b.committed_now = true
	)).is_true()


func test_a_throw_wakes_it() -> void:
	assert_bool(_wakes(func(b): b.task.primitive = &"throw")).is_true()


func test_a_door_being_worked_wakes_it() -> void:
	assert_bool(_wakes(func(b): b._loco.leaves.door = true)).is_true()


func test_a_detour_round_a_refused_door_wakes_it() -> void:
	assert_bool(_wakes(func(b): b._loco.leaves.detour = true)).is_true()


func test_a_grenade_evade_wakes_it() -> void:
	assert_bool(_wakes(func(b): b.grenades.evade = true)).is_true()


func test_a_primed_ambusher_wakes_it() -> void:
	assert_bool(_wakes(func(b): b.orders.prime = true)).is_true()


func test_a_blind_npc_wakes_it() -> void:
	assert_bool(_wakes(func(b): b._character.stun.blind = true)).is_true()


func test_an_entry_approach_wakes_it_within_two_hundred_px_of_its_doorway() -> void:
	var near := func(away: float) -> bool:
		return _wakes(func(b):
			b.task.primitive = &"entry"
			b._character.global_position = DOORWAY + Vector2(away, 0)
		)
	assert_bool(near.call(Gait.ENTRY_FAR - 1.0)).is_true()
	assert_bool(near.call(Gait.ENTRY_FAR + 1.0)).is_false()


func test_a_guards_detour_wakes_an_entry_approach_wherever_it_is() -> void:
	assert_bool(_wakes(func(b):
		b.task.primitive = &"entry"
		b.entries.resume = { "kind": "detour" }
	)).is_true()


func test_an_entry_with_no_doorway_read_yet_wakes_it() -> void:
	assert_bool(_wakes(func(b):
		b.task.primitive = &"entry"
		b._entry.state.geo = {}
	)).is_true()


func test_an_entry_past_its_approach_wakes_it_wherever_it_is() -> void:
	assert_bool(_wakes(func(b):
		b.task.primitive = &"entry"
		b._entry.state.phase = "stack"
	)).is_true()


## One stand-in part, with every flag and answer the gait reads of any of its parts (a part reads
## only its own: the door leaves `door` and `detour`, the grenades `evade`, the orders `prime`, the
## stun `blind`, the entry's state `phase` and `geo`, the entries `resume`).
class Part:
	extends RefCounted
	var door := false
	var detour := false
	var evade := false
	var prime := false
	var blind := false
	var phase := "approach"
	var geo := { "pos": DOORWAY }
	var resume := {}
	var leaves: Part
	var state: Part


	func working() -> bool:
		return door


	func detouring() -> bool:
		return detour


	func evading() -> bool:
		return evade


	func primed() -> bool:
		return prime


	func is_blind() -> bool:
		return blind


## The character the gait reads: where it stands and its stun.
class FakeCharacter:
	extends Node2D
	var stun := Part.new()


## The behaviour's side of the gait: the parts it reaches, all at rest.
@warning_ignore("unused_private_class_variable")
class FakeBehavior:
	extends Node
	var task := RunningLeaf.new()
	var _character := FakeCharacter.new()
	var _entry := Part.new()
	var _loco := Part.new()
	var entries := Part.new()
	var grenades := Part.new()
	var orders := Part.new()
	var committed_now := false


	func _init() -> void:
		_entry.state = Part.new()
		_loco.leaves = Part.new()


	func committed() -> bool:
		return committed_now
