extends GameTest
## The district's shared-art requests are painted by the pre-warm with the same keys and pixels as
## the synchronous renderer. References are painted first, their cache entries removed, then the
## worker warm must restore exactly those images before the ordinary render fallback is asked.

const SHARED := "res://scenes/objects/shared_textures.gd"


func describe() -> Dictionary:
	return {
		"name": "Pre-warm paints the district's shared textures",
		"description": "Every shared-texture request is cached by worker warming with exactly the "
			+ "pixels a synchronous paint produces.",
		"tags": ["art", "perf"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var shared = load(SHARED)
	if not t.require(shared != null, "Objects publishes the district's shared-texture requests"):
		return
	var requests: Array = DistrictPrewarm.requests()
	if not t.require(not requests.is_empty(), "the shared-texture list is not empty"):
		return
	var art: Script = preload("res://scenes/art/pixel_art.gd")
	var has_warm: bool = art.get_script_method_list().any(
		func(method: Dictionary) -> bool: return method.get("name") == &"warm",
	)
	if not t.require(has_warm, "PixelArt accepts shared-texture warm requests"):
		return
	var references: Array[PackedByteArray] = []
	var keys := _reference_keys(requests, references)
	art.call(&"warm", requests)
	art.call(&"finish_warming")
	var cache: Dictionary = PixelArt._cache
	for i in requests.size():
		if not t.require(cache.has(keys[i]), "request %d is cached after the warm" % i):
			continue
		var texture := _render(requests[i])
		t.check(
			texture.get_image().get_data() == references[i],
			"request %d has the synchronous paint's pixels" % i,
		)
	_district_asks_only_warm_keys(t)


## Paint every request synchronously, retain its pixels and remove exactly its cache key.
func _reference_keys(requests: Array, references: Array[PackedByteArray]) -> Array:
	var cache: Dictionary = PixelArt._cache
	var emissive: Dictionary = PixelArt._emissive
	var keys: Array = []
	for request: Dictionary in requests:
		var texture := _render(request)
		references.append(texture.get_image().get_data())
		for key in cache:
			if cache[key] == texture:
				keys.append(key)
				cache.erase(key)
				emissive.erase(key)
				break
	return keys


func _render(request: Dictionary) -> Texture2D:
	return PixelArt.render(
		request["painter"],
		request["size"],
		request["color"],
		request["facing"],
		request["opts"],
	)


## A district built after the warm paints none of the fixed shared art itself: its crossings, shell
## decor, awnings and signs over a door and tower shadows are all keys the warm already cached.
func _district_asks_only_warm_keys(t: TestContext) -> void:
	var cache: Dictionary = PixelArt._cache
	var warm_keys := cache.keys()
	WorldGen.generate_district(7, "", Vector2.ZERO, t.world)
	var painted: Array = []
	for key: String in cache:
		if not warm_keys.has(key) and _fixed_shared(key):
			painted.append(key)
	t.check(painted.is_empty(), "the district painted shared art the warm lacks: %s" % [painted])


## Whether `key` is a texture the warm covers exactly: a crossing, a shell decoration, a tower
## shadow or an awning or sign hung over a door (a podium segment or a road glyph depends on the
## seed, so only some are warm).
func _fixed_shared(key: String) -> bool:
	return (key.contains("crossing_painter") or key.contains("shell_decor_painter")
			or key.contains("shadow_painter")
			or (key.contains("awning_painter") and key.contains("overhang")))
