extends GameTest
## D12 (#194): a chip knocked off a surface flies in the twin 3D space and comes to rest where the
## 3D surface is. Chips thrown from a hit on a desk's top (31 px up) lie on the top at its height,
## not on the floor under it; the layer's record carries the height. The same hit's chips thrown
## from the floor lie at the floor's.

const WOOD := { "color": Color(0.6, 0.4, 0.2), "material": "wood" }
const DESK := Vector2(300, 100)
const HALF := Vector2(60, 25)
const TOP := 31.0
const OPEN := Vector2(500, 300)


func describe() -> Dictionary:
	return {
		"name": "Chips thrown off a desk's top lie on the desk top",
		"description": "A wooden hit at the middle of a desk's 31 px top sprays chips that all "
			+ "come to rest on the top (the record says 31 px up); a hit on the open floor "
			+ "sprays chips that lie on the floor.",
		"tags": ["debris", "physics", "3d", "furniture", "heights"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", true)
	s.object(&"desk", "desk", DESK)


func run(t: TestContext) -> void:
	await t.frames(3)
	DebrisSpawner.spawn(DESK, Vector2.RIGHT, t.world, WOOD, TOP)
	await t.until(func(): return _flying(t) == 0, 4.0)
	var layer := DebrisLayer.find(t.world)
	if not t.require(layer != null and layer.count() >= 3, "the chips came to rest in the layer"):
		return
	for chip: Dictionary in layer.items():
		var at: Vector2 = chip["at"]
		t.check(
			absf(at.x - DESK.x) <= HALF.x and absf(at.y - DESK.y) <= HALF.y,
			"a chip lies within the desk's footprint (%s)" % str(at.round()),
		)
		t.check(
			absf(float(chip.get("height", -1.0)) - TOP) <= 2.0,
			"on its top (%.1f px up, the top at %.0f)" % [float(chip.get("height", -1.0)), TOP],
		)
	var on_top := layer.count()
	DebrisSpawner.spawn(OPEN, Vector2.RIGHT, t.world, WOOD, 20.0)
	await t.until(func(): return _flying(t) == 0, 4.0)
	var floor_chips: Array = layer.items().slice(on_top)
	t.check(floor_chips.size() >= 3, "the open hit's chips came to rest")
	for chip: Dictionary in floor_chips:
		t.check(
			float(chip.get("height", -1.0)) <= 1.5,
			"a chip thrown in the open lies on the floor (%.1f px up)" % chip.get("height", -1.0),
		)


## How many chips are still flying (nodes under the world).
func _flying(t: TestContext) -> int:
	return t.world.get_children().filter(
		func(n: Node) -> bool:
			var script: Script = n.get_script()
			return script != null and script.resource_path.ends_with("physics/debris.gd")
	).size()
