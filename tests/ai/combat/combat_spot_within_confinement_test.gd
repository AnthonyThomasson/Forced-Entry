extends GameTest
## Combat's choice of spot (ticket #97's C6): a peek with no line to its contact walks only to a
## spot its confinement lets it act at, and with no such spot closes on the contact where it may act
## there, else holds where it stands. `Combat` is driven here with a stand-in character, locomotion
## and perception (no world), the confinement fed plain rooms (two side by side, sharing the wall at
## x = 100: the hall west of it, the kitchen east); the arena the test world builds plays no part.

const Confinement := preload("res://scenes/ai/perception/perception_confinement.gd")
const Combat := preload("res://scenes/ai/behavior/combat.gd")
const HALL := { "key": "hall", "type": "hall", "rect": Rect2(0, 0, 100, 100) }
const KITCHEN := { "key": "kitchen", "type": "kitchen", "rect": Rect2(100, 0, 100, 100) }
const IN_HALL := Vector2(50, 50)
const IN_KITCHEN := Vector2(150, 50)
const OUTSIDE := Vector2(300, 50)

## The stand-in nodes built so far, freed when the test ends.
var _nodes: Array = []


func describe() -> Dictionary:
	return {
		"name": "A fight walks only to a spot its confinement allows",
		"description": "Combat driven with stand-ins: a territorial NPC peeks from a spot in the "
			+ "house, not a nearer one outside; with no fire spot a leashed NPC closes on a "
			+ "contact within its leash and holds against one beyond it.",
		"tags": ["ai", "combat", "territory", "leash", "unit"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	var in_kitchen_corner := Vector2(180, 80)
	var loco := _peek(_confinement(true, Vector2.INF, 0.0), IN_HALL, [OUTSIDE, in_kitchen_corner])
	t.expect_eq(
		loco.dest,
		in_kitchen_corner,
		"a territorial NPC fighting a contact in the kitchen peeks from the kitchen spot, not the "
			+ "nearer one outside the house (walks to %s)" % loco.dest,
	)
	loco = _peek(_confinement(false, IN_HALL, 200.0), IN_HALL, [])
	t.expect_eq(
		loco.dest,
		IN_KITCHEN,
		"with no fire spot, a leashed NPC closes on a contact within its leash (walks to %s)"
			% loco.dest,
	)
	loco = _peek(_confinement(false, IN_HALL, 60.0), IN_HALL, [])
	t.expect_eq(
		loco.dest,
		IN_HALL,
		"with no fire spot, it holds where it stands against a contact off its leash (walks to %s)"
			% loco.dest,
	)
	for n in _nodes:
		n.free()


## A confinement over the two rooms, refreshed with `territorial` and the leash (no order).
func _confinement(territorial: bool, center: Vector2, radius: float) -> RefCounted:
	var c: RefCounted = Confinement.new()
	c.rooms = [HALL, KITCHEN]
	c.refresh(territorial, {}, center, radius)
	return c


## One peek of a fresh `Combat` for an NPC standing at `at`, confined by `c`, with no line to its
## contact in the kitchen and offered the fire and cover spots `spots`: the locomotion, which
## records where it was sent.
func _peek(c: RefCounted, at: Vector2, spots: Array) -> FakeLoco:
	var loco := FakeLoco.new()
	var perception := FakePerception.new()
	perception.confinement = c
	perception.spots = spots
	var me := FakeCharacter.new()
	me.global_position = at
	var tuning := NpcTuning.defaults()
	_nodes.append_array([loco, perception, me, tuning])
	var combat := Combat.new()
	combat.setup(loco, perception, tuning)
	combat.bind(me)
	combat.peek_cover(0.016, null, IN_KITCHEN)
	return loco


## Locomotion that records where it is sent.
class FakeLoco extends Node:
	var dest := Vector2.INF

	func move_to(p: Vector2, _arrive := 0.0) -> void:
		dest = p


## Perception with no line to anything, offering `spots` as both the fire and the cover spots, and
## the confinement it is handed.
class FakePerception extends Node:
	var confinement: RefCounted
	var spots: Array = []

	func combat_spots(_node: Node2D, _pos: Vector2, _radius: float) -> Dictionary:
		return { "fire": spots.duplicate(), "cover": spots.duplicate() }

	func has_line_to(_node: Node2D, _point: Vector2) -> bool:
		return false

	func note_engaged() -> void:
		pass


## A character with just where it stands and faces, and a movement intent `Combat` may write.
class FakeCharacter extends Node:
	var global_position := Vector2.ZERO
	var facing := Vector2.RIGHT
	var movement := FakeMovement.new()


## The stand-in character's movement intent.
class FakeMovement extends RefCounted:
	var move_input := Vector2.ZERO
