extends GameTest
## The district's pre-warm paints the flat art of every catalogued furniture piece
## (`DistrictPrewarm.furniture_requests`, #193 phase 2b), so a 3D match paints none of it on the
## main thread: after the warm, a piece's `FurnitureArt.of` (at a palette tone, rotated, facing a
## side, with a neon trim, with an overhang) files no flat texture of its own.

const ObjectArt := preload("res://scenes/objects/art/object_art.gd")


func describe() -> Dictionary:
	return {
		"name": "The pre-warm paints every furniture piece's flat art",
		"description": "After DistrictPrewarm.furniture_requests are warmed, FurnitureArt.of for "
			+ "a palette-toned, rotated, side-facing, neon-trimmed or overhanging piece adds no "
			+ "texture to the cache.",
		"tags": ["art", "perf", "furniture"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	var tone: Color = ArrangementDefinitions.palette_tones("fabric")[1]
	s.object(&"sofa", "sofa", Vector2(100, 100), { "color": tone })
	s.object(&"sofa_side", "sofa", Vector2(300, 100), {
		"color": tone, "facing": Vector2.LEFT, "rotated": true,
	})
	s.object(&"tv", "tv", Vector2(500, 100), { "neon": "magenta" })
	s.object(&"lamp", "streetlight", Vector2(100, 300), { "facing": Vector2.RIGHT })
	s.object(&"awning", "awning", Vector2(300, 300), { "facing": Vector2.UP })


func run(t: TestContext) -> void:
	var requests := DistrictPrewarm.furniture_requests()
	t.require(requests.size() > 100, "the catalogue has flat requests (%d)" % requests.size())
	PixelArt.warm(requests)
	PixelArt.finish_warming()
	var before := PixelArt._cache.size()
	for id: StringName in [&"sofa", &"sofa_side", &"tv", &"lamp", &"awning"]:
		var spec := FurnitureSpec.of(t.object(id))
		t.check(not FurnitureArt.of(spec).is_empty(), "%s has art" % id)
	t.check(
		PixelArt._cache.size() == before,
		"no flat texture was painted by the pieces (%d new)" % (PixelArt._cache.size() - before),
	)
