extends "res://tests/navigation/bake_matches_recorded_colliders_test.gd"
## `navigation/bake_matches_recorded_colliders` on a house (a lone house plans on its one map, a
## ring of outdoors round its rooms): the walls, holes, navmesh and routes baked from the twins
## against what the 2D colliders gave (`tests/_navigation/bake_baseline.gd`).

const Piece := preload("res://tests/_objects/piece_probe.gd")
const HOUSE_SEED := 1
const HOUSE_PLAN := "garage_home"


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "A bake from the twins matches the recorded bake from the colliders (house)"
	d["tags"] = ["navigation", "bake", "house", "twins"]
	return d


func configure(s: TestSetup) -> void:
	s.house(HOUSE_SEED, HOUSE_PLAN)
	s.object(&"shelf", "bookshelf", Vector2.ZERO)
	s.actor(&"stander", &"puppet", Vector2.ZERO)
	s.switch(&"nav.rebake", false)


func _record() -> Dictionary:
	return Baseline.HOUSE


func _root(t: TestContext) -> Node2D:
	return t.world.get("house") as Node2D


func _site(_t: TestContext, root: Node2D) -> NavSite:
	return NavSite.new(root, WorldGen.get_rooms(root), RADIUS)


## A shot-up wall, then a character at rest and a bookshelf laid on its side, each in a room of its
## own: the character's hole is the recorded one (the same 10-gon: the twin's yaw is the body's),
## and the holes with the shelf tipped have the recorded area to `AREA_SHARE`.
func _extras(t: TestContext, root: Node2D) -> void:
	await super._extras(t, root)
	var after: Dictionary = _record()["after"]
	var rooms := WorldGen.get_rooms(root)
	var stander: Node2D = t.actor(&"stander")
	stander.global_position = (rooms[0]["rect"] as Rect2).get_center()
	var shelf: Node2D = t.object(&"shelf")
	shelf.global_position = (rooms[1]["rect"] as Rect2).get_center()
	await t.frames(TwinSpace.PARK_SPREAD + 6)
	Knockback.push(shelf, Vector2(5000.0, 0.0), Vector2.ZERO, Piece.top(shelf) - 4.0)
	await t.seconds(0.3)
	await Piece.settle(t, shelf, 10.0)
	t.require(Piece.lean(shelf) > 60.0, "premise: the bookshelf lies on its side")
	await t.frames(2)
	var chars := NavBuilder.character_holes(root.get_parent())
	var holes := NavBuilder.furniture_holes(root) + chars
	var want: float = after["holes_area"]
	t.check(
		absf(_area(holes) - want) <= want * AREA_SHARE,
		("the holes with the shelf tipped are the recorded area to %d%% (%.0f px² recorded, "
			+ "%.0f now)") % [int(AREA_SHARE * 100.0), want, _area(holes)],
	)
	t.check(
		chars.size() == after["characters"]
			and absf(_area(chars) - float(after["characters_area"])) <= AREA_EPSILON,
		("a character at rest has the recorded hole (%d recorded, %d now; %.1f px² recorded, "
			+ "%.1f now)") % [
				after["characters"],
				chars.size(),
				after["characters_area"],
				_area(chars),
			],
	)
