extends GameTest
## A tipped piece is carved where it lies (#194 furn3d, D14): a bookshelf knocked over toward +x
## covers floor that was free; the nav re-bake rule (the holes changed, so the map is baked again)
## carves it, and the floor it stood on is floor again.

const SHELF := Vector2(300, 200)
## Free floor the standing shelf (40 px wide) leaves but the one lying along +x covers (it reaches
## about 75 px out from its foot), and the floor the standing one covered.
const COVERED := Vector2(375, 200)
const FOOT := Vector2(300, 200)
const WAIT := 12.0


func describe() -> Dictionary:
	return {
		"name": "The nav re-bakes around a tipped piece",
		"description": "A bookshelf is knocked over toward +x: the nav map is re-baked on its own "
			+ "and the floor the shelf now lies on is carved out of it.",
		"tags": ["navigation", "rebake", "furniture", "tipping", "3d"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.object(&"shelf", "bookshelf", SHELF)
	s.switch(&"nav.rebake", true)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var map := region.get_navigation_map()
	if not t.require(NavBuilder.ready(map), "premise: the map answers"):
		return
	t.require(
		NavBuilder.snap(map, COVERED).distance_to(COVERED) < 1.0,
		"premise: the floor 75 px out is free while the shelf stands",
	)
	t.require(
		NavBuilder.snap(map, FOOT).distance_to(FOOT) > 5.0,
		"premise: the standing shelf is carved where it stands",
	)
	var shelf := t.object(&"shelf")
	Knockback.push(shelf, Vector2(9000.0, 0.0), Vector2.ZERO, 70.0)
	t.check(
		await t.until(
			func() -> bool: return NavBuilder.snap(map, COVERED).distance_to(COVERED) > 5.0, WAIT,
		),
		"once it lies over it, the floor 75 px out is carved out of the re-baked map",
	)
