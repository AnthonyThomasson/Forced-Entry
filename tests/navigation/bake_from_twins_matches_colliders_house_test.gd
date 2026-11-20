extends "res://tests/navigation/bake_from_twins_matches_colliders_test.gd"
## `navigation/bake_from_twins_matches_colliders` on a house (a lone house plans on its one map, a
## ring of outdoors round its rooms): the walls, holes, navmesh and routes baked from the twins
## against the 2D colliders'.

const HOUSE_SEED := 1
const HOUSE_PLAN := "garage_home"


func describe() -> Dictionary:
	var d := super.describe()
	d["name"] = "A bake from the twins matches a bake from the colliders (house)"
	d["tags"] = ["navigation", "bake", "house", "twins"]
	return d


func configure(s: TestSetup) -> void:
	s.house(HOUSE_SEED, HOUSE_PLAN)
	s.switch(&"nav.rebake", false)


func _root(t: TestContext) -> Node2D:
	return t.world.get("house") as Node2D


func _site(_t: TestContext, root: Node2D) -> NavSite:
	return NavSite.new(root, WorldGen.get_rooms(root), RADIUS)
