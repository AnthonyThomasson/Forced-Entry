extends GameTest
## Carried stock is carved like a piece (#194, D21 decision, `docs/stacked-items.md` SI13):
## the crates a crate stack carries and the wrapped boxes on a pallet stand taller than a step, so
## each is a nav hole as a floor stack is (`navigation/house_items_carve_like_pieces`); the pallet
## under them (5 px) is walked over. A room holds a crate stack and a loaded pallet with a lane
## between and beside them: an NPC sent across it arrives, and its route does not run through a
## hole.

const FROM := Vector2(60.0, 200.0)
const TO := Vector2(740.0, 200.0)
const STACK := Vector2(300.0, 200.0)
const PALLET := Vector2(460.0, 200.0)
const ARRIVE := 24.0
const WAIT := 25.0


func describe() -> Dictionary:
	return {
		"name": "An NPC crosses a room of carried stock",
		"description": "A crate stack and a loaded pallet (their crates and wrapped boxes loose "
			+ "items) stand across a room: the crates and boxes are holes, the pallet is not, "
			+ "and an NPC sent across arrives without standing stuck.",
		"tags": ["navigation", "items", "stacking", "unbake", "ai"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.object(&"stack", "crate_stack", STACK)
	s.object(&"pallet", "wrapped_pallet", PALLET)
	s.actor(&"walker", &"puppet", FROM)
	s.switch(&"nav.rebake", true)


func _carve(place: Node2D, key: String) -> Array:
	return RoomItems.carry(
		place, ObjectDefinitions.get_definition(key), place.get_parent(), "test"
	)


func _carved(holes: Array, point: Vector2) -> bool:
	return holes.any(
		func(hole: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(point, hole)
	)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var placed := _carve(t.object(&"stack"), "crate_stack")
	placed += _carve(t.object(&"pallet"), "wrapped_pallet")
	await t.seconds(1.0)
	var holes := NavBuilder.furniture_holes(t.world)
	var crates := 0
	var boxes := 0
	for entry: Dictionary in placed:
		var node: Node2D = entry["node"]
		var key: String = entry["key"]
		if key == "pallet":
			t.check(
				NavHoles.cut(node).is_empty(), "the pallet under the boxes is walked over: no hole"
			)
			continue
		t.check(not NavHoles.cut(node).is_empty(), "a carried %s is cut like a piece" % key)
		t.check(_carved(holes, node.global_position), "a carried %s stands in a hole" % key)
		crates += 1 if key == "crate" else 0
		boxes += 1 if key == "wrapped_box" else 0
	t.require(crates >= 2 and boxes == 4, "premise: %d crates, %d boxes carried" % [crates, boxes])
	var map := NavWorld.map_of(t.world)
	t.require(NavBuilder.ready(map), "the nav map is baked")
	var walker := t.puppet(&"walker")
	walker.walk_to(TO)
	t.check(
		await t.until(
			func() -> bool: return t.actor(&"walker").global_position.distance_to(TO) < ARRIVE,
			WAIT,
		),
		"the NPC crosses the stockroom and arrives (%.0f px short)"
		% t.actor(&"walker").global_position.distance_to(TO),
	)
