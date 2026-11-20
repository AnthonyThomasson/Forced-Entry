extends "res://tests/navigation/bake_from_twins_matches_colliders_test.gd"
## `navigation/bake_from_twins_matches_colliders` on a house (a lone house plans on its one map, a
## ring of outdoors round its rooms): the walls, holes, navmesh and routes baked from the twins
## against the 2D colliders'.

const Piece := preload("res://tests/_objects/piece_probe.gd")
const HOUSE_SEED := 1
const HOUSE_PLAN := "garage_home"


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "A bake from the twins matches a bake from the colliders (house)"
	d["tags"] = ["navigation", "bake", "house", "twins"]
	return d


func configure(s: TestSetup) -> void:
	s.house(HOUSE_SEED, HOUSE_PLAN)
	s.object(&"shelf", "bookshelf", Vector2.ZERO)
	s.actor(&"stander", &"puppet", Vector2.ZERO)
	s.switch(&"nav.rebake", false)


func _root(t: TestContext) -> Node2D:
	return t.world.get("house") as Node2D


func _site(_t: TestContext, root: Node2D) -> NavSite:
	return NavSite.new(root, WorldGen.get_rooms(root), RADIUS)


## A shot-up wall, then a character at rest and a bookshelf laid on its side, each in a room of its
## own: the character's hole is the old one (the same 10-gon: the twin's yaw is the body's), the
## shelf's the old tipped hull's to within a few percent.
func _extras(t: TestContext, root: Node2D) -> void:
	await super._extras(t, root)
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
	var old_hole := Reference.cut(shelf)
	var new_hole := NavHoles.cut(shelf)
	t.check(
		new_hole.size() >= 3
			and absf(_area([new_hole]) - _area([old_hole])) <= 0.05 * _area([old_hole]),
		"the tipped shelf's hole is the old one's to 5%% (%.0f px² old, %.0f px² new)"
			% [_area([old_hole]), _area([new_hole])],
	)
	var old_chars := Reference.characters(root.get_parent())
	var new_chars := NavBuilder.character_holes(root.get_parent())
	t.check(
		old_chars.size() == 1 and new_chars.size() == 1
			and _same_corners(old_chars[0], new_chars[0]),
		"a character at rest has the old hole (%d old, %d new)" % [
			old_chars.size(),
			new_chars.size(),
		],
	)
