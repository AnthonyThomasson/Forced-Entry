extends GameTest
## D12 (#194): a chip hits a wall's real face and bounces off it: thrown from 8 px off the west wall
## straight at it (at the height of a hit), every chip comes to rest in the room, none beyond the
## wall's face; a 2D toss would carry it through.

const METAL := { "color": Color.GRAY, "material": "metal" }
## The arena's west wall: its inner face is 6 px in. The chips start 8 px off it.
const FACE := 6.0
const AT := Vector2(14, 250)


func describe() -> Dictionary:
	return {
		"name": "A chip thrown at a wall bounces off its face",
		"description": "Chips sprayed at the west wall from 8 px off it at a hit's height all "
			+ "rest on this side of the wall's face.",
		"tags": ["debris", "physics", "3d", "wall"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", true)


func run(t: TestContext) -> void:
	await t.frames(3)
	for _i in 5:
		DebrisSpawner.spawn(AT, Vector2.LEFT, t.world, METAL, 40.0)
	await t.until(func(): return _flying(t) == 0, 4.0)
	var layer := DebrisLayer.find(t.world)
	if not t.require(layer != null and layer.count() >= 10, "the chips came to rest"):
		return
	var nearest := INF
	for chip: Dictionary in layer.items():
		nearest = minf(nearest, (chip["at"] as Vector2).x)
	t.check(nearest >= FACE, "no chip lies beyond the wall's face (nearest x %.1f)" % nearest)
	t.check(nearest < 20.0, "premise: chips did fly at the wall (nearest x %.1f)" % nearest)


## How many chips are still flying (nodes under the world).
func _flying(t: TestContext) -> int:
	return t.world.get_children().filter(
		func(n: Node) -> bool:
			var script: Script = n.get_script()
			return script != null and script.resource_path.ends_with("physics/debris.gd")
	).size()
