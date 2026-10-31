extends GameTest
## DR8: a swinging door nudges a character standing in its arc out of the way, the one who opened it
## as well, and stops short at furniture and at a body that cannot move further (a puppet with a
## fridge at its back), staying where it stopped. The arc is the quarter disc a leaf sweeps from
## shut to open, east of the wall here (the doors swing east, hinged on their upper jamb).

const JAMB := 20.0
const LEAF := 40.0
const FULL := 90.0
const SWING := 0.4
## A character's radius, with a pixel of slack for the leaf's own thickness and the rest.
const CLEAR := 14.0 - 1.5


func describe() -> Dictionary:
	return {
		"name": "A swinging door nudges characters aside and stops at obstacles",
		"description": "A puppet in the arc of a door opened toward it, and the puppet that opens "
			+ "it, are moved clear of the leaf and the door opens fully; a chair in the arc stops "
			+ "the door short and it stays there; so does a puppet pinned against a fridge.",
		"tags": ["door", "objects", "nudge"],
		"timeout": 12.0,
	}


func _doorway(y: float, id: String) -> Dictionary:
	return {
		"pos": Vector2(400, y), "width": 52.0,
		"door": {
			"name": id, "material": "hollow", "style": "flush",
			"hinge": Vector2(400, y - JAMB), "swing_into": Vector2.RIGHT,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 700) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 700) },
	], [
		_doorway(100.0, "pushed"), _doorway(250.0, "opened"),
		_doorway(400.0, "chaired"), _doorway(550.0, "pinned"),
	])
	s.von_down()
	s.actor(&"pushed", &"puppet", Vector2(420, 108))
	s.actor(&"opener", &"puppet", Vector2(420, 258))
	s.object(&"chair", "chair", Vector2(425, 412))
	s.actor(&"pinned", &"puppet", Vector2(418, 556))
	s.object(&"fridge", "fridge", Vector2(466, 556))


func run(t: TestContext) -> void:
	await t.seconds(0.4)
	var starts := {}
	for id: StringName in [&"pushed", &"opener", &"pinned"]:
		starts[id] = t.actor(id).global_position
	var chair_at: Vector2 = t.object(&"chair").global_position
	var fridge_at: Vector2 = t.object(&"fridge").global_position
	t.object(&"pushed").toggle(null)
	t.object(&"opened").toggle(t.actor(&"opener"))
	t.object(&"chaired").toggle(null)
	t.object(&"pinned").toggle(null)
	await t.seconds(SWING + 0.4)

	_cleared(t, starts)
	await _stopped_short(t, chair_at, fridge_at, starts)


## The doors with a character in the arc open fully and leave it clear of the leaf.
func _cleared(t: TestContext, starts: Dictionary) -> void:
	for pair in [[&"pushed", &"pushed"], [&"opened", &"opener"]]:
		var door = t.object(pair[0])
		var puppet := t.actor(pair[1])
		t.check(
			door.angle() == FULL,
			"the %s door opens fully with a character in its arc (%.0f)" % [pair[0], door.angle()],
		)
		var from_leaf := _distance_to_leaf(door, puppet.global_position)
		t.check(
			from_leaf >= CLEAR,
			"and the character is moved clear of the leaf (%.1f px from it)" % from_leaf,
		)
		var moved: float = puppet.global_position.distance_to(starts[pair[1]])
		t.check(moved > 3.0, "it was moved (%.1f px)" % moved)


## The chair and the pinned character stop their doors short; they stay there and nothing is shoved.
func _stopped_short(
	t: TestContext,
	chair_at: Vector2,
	fridge_at: Vector2,
	starts: Dictionary,
) -> void:
	var chaired = t.object(&"chaired")
	t.check(
		chaired.angle() > 5.0 and chaired.angle() < FULL - 10.0,
		"a chair in the arc stops the door short (%.0f)" % chaired.angle(),
	)
	var stopped_at: float = chaired.angle()
	await t.seconds(0.5)
	t.check(chaired.angle() == stopped_at, "and it stays there (%.0f)" % chaired.angle())
	t.check(
		t.object(&"chair").global_position.distance_to(chair_at) < 1.0,
		"the chair was not pushed",
	)
	var pinned = t.object(&"pinned")
	t.check(
		pinned.angle() > 5.0 and pinned.angle() < FULL - 10.0,
		"a character with a fridge at its back stops the door short (%.0f)" % pinned.angle(),
	)
	t.check(
		t.object(&"fridge").global_position.distance_to(fridge_at) < 1.0
			and t.actor(&"pinned").global_position.distance_to(starts[&"pinned"]) < 6.0,
		"neither the fridge nor the character was shoved through it",
	)


## How far `point` is from the leaf's line (px).
func _distance_to_leaf(door: Node2D, point: Vector2) -> float:
	var pose: Transform2D = door.global_transform
	var half: Vector2 = door.leaf_size() * 0.5
	var near := Geometry2D.get_closest_point_to_segment(
		point, pose * Vector2(-half.x, 0.0), pose * Vector2(half.x, 0.0)
	)
	return point.distance_to(near)
