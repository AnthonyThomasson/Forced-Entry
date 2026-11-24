extends GameTest
## A small item lying within a step (#194 stack-a, D20, `docs/stacked-items.md`) is walked over, so
## it is no hole in the nav bake: a plate, a cup and a book on the floor leave the baked map open
## under them, while a crate and a box (taller than a step) are carved like any piece.

const PLATE_AT := Vector2(150, 150)
const CUP_AT := Vector2(250, 150)
const BOOK_AT := Vector2(350, 150)
const CRATE_AT := Vector2(150, 300)
const BOX_AT := Vector2(300, 300)


func describe() -> Dictionary:
	return {
		"name": "Walk-over items leave the nav map open",
		"description": "A plate, a cup and a book on the floor are in no nav hole and the baked "
			+ "map has floor under each; a crate and a box are holes and the map has none "
			+ "under them.",
		"tags": ["navigation", "items", "stacking", "furniture"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.object(&"plate", "plate", PLATE_AT)
	s.object(&"cup", "cup", CUP_AT)
	s.object(&"book", "book", BOOK_AT)
	s.object(&"crate", "crate", CRATE_AT)
	s.object(&"box", "box", BOX_AT)


## Whether some hole of `holes` holds `point`.
func _carved(holes: Array, point: Vector2) -> bool:
	return holes.any(
		func(hole: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(point, hole)
	)


func run(t: TestContext) -> void:
	await t.frames(5)
	var holes := NavBuilder.furniture_holes(t.world.house)
	for id: StringName in [&"plate", &"cup", &"book"]:
		var at: Vector2 = t.object(id).global_position
		t.check(not _carved(holes, at), "%s is in no nav hole" % id)
	for id: StringName in [&"crate", &"box"]:
		var at: Vector2 = t.object(id).global_position
		t.check(_carved(holes, at), "%s is a nav hole" % id)
	var map := NavWorld.map_of(t.world)
	if not t.require(NavBuilder.ready(map), "the nav map is baked"):
		return
	for id: StringName in [&"plate", &"cup", &"book"]:
		var at: Vector2 = t.object(id).global_position
		var off := NavBuilder.snap(map, at).distance_to(at)
		t.check(off < 2.0, "the baked map is open under the %s (%.1f px to floor)" % [id, off])
	for id: StringName in [&"crate", &"box"]:
		var at: Vector2 = t.object(id).global_position
		var off := NavBuilder.snap(map, at).distance_to(at)
		t.check(off > 6.0, "the baked map is closed under the %s (%.1f px to floor)" % [id, off])
