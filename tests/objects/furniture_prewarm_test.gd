extends GameTest
## The district's pre-warm paints the flat art of every catalogued furniture piece
## (`DistrictPrewarm.furniture_requests`, #193 phase 2b), so a 3D match paints none of it on the
## main thread: after the warm, a piece's `FurnitureArt.of` (at a palette tone, rotated, facing a
## side, with a neon trim, with an overhang) files no flat texture of its own.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const ObjectArt := preload("res://scenes/objects/art/object_art.gd")
const SharedTextures := preload("res://scenes/objects/shared_textures.gd")


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
	_two_d_boot_warms_no_furniture(t)
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
	_district_paints_no_flat_art(t)


## A built district (its houses' furniture, the street's, the towers' podiums, awnings and decor)
## asks for no flat art the warm lacks: the art of every piece with one is already cached.
func _district_paints_no_flat_art(t: TestContext) -> void:
	for seed_value in [7, 11]:
		var root := WorldGen.generate_district(seed_value, "", Vector2.ZERO, t.world)
		var before := PixelArt._cache.keys()
		var asked := 0
		for body: Node in PlanProbe.pieces_under(root):
			var look: Variant = body.get("look")
			if look is Object and String((look as Object).get("art")) != "":
				FurnitureArt.of(FurnitureSpec.of(body as Node2D))
				asked += 1
		var fresh: Array = []
		for key: String in PixelArt._cache:
			if key.ends_with("|flat") and not before.has(key):
				fresh.append(key.get_slice("|", 0).get_file())
		t.check(asked > 50, "the district %d has furniture (%d pieces)" % [seed_value, asked])
		t.check(
			fresh.is_empty(),
			"district %d painted flat art the warm lacks: %s" % [seed_value, fresh],
		)


## The warm a run starts at boot holds no flat furniture request (the structure's tiles and the
## shared street decals stay in it): furniture's flat art is warmed only when a match is coming
## (`WorldGen.prewarm(true)`; a no-op headless).
func _two_d_boot_warms_no_furniture(t: TestContext) -> void:
	var structure := DistrictPrewarm.structure_requests()
	var shared := SharedTextures.requests()
	var flat := DistrictPrewarm.requests().filter(
		func(request: Dictionary) -> bool:
			return (
				request.get("flat", false)
				and not structure.has(request)
				and not shared.has(request)
			)
	)
	t.check(
		flat.is_empty(),
		"the boot warm holds %d flat requests besides the structure's" % flat.size(),
	)
	WorldGen.prewarm(false)
	WorldGen.prewarm(true)
	t.check(DistrictPrewarm.requests().size() > 0, "the shared warm requests are still there")
