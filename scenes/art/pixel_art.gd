class_name PixelArt
## Renders painters into cached pixel-art textures (Art domain: the entry point the Objects,
## Character, Items and Vehicles domains paint through for the 3D render). A PAINTER is any script
## with `static func paint(canvas: PixelCanvas, base: Color, material: String, opts: Dictionary)`
## that draws in a canonical frame, front toward +y, width across the front, on a canvas with no
## light (the 3D lights shade the mesh):
##   • render_flat() / emissive_flat(): the painter's albedo, one canonical texture per piece (no
##     facing, no angle), under the `|flat` key; a decal's `facing` turns the picture in quarter
##     turns.
## Textures are cached by their inputs (static, so they survive scene reloads); a piece's random
## detail is seeded by its inputs minus its orientation, so it doesn't change as the piece turns.
## What a painter draws `glowing` (PixelCanvas: a screen's face, a tube, a bulb) is kept as a
## second, EMISSIVE texture of only those pixels (`emissive_flat()`), from the same paint, for the
## meshes that glow.
## Every entry point takes the painter's `opts`, which it hands the painter as they are, but for one
## key of its own: `material` (String, default ""), the `material` the painter's `paint` is given
## (the surface finish its tones are drawn in: "fabric", "metal", ...), taken off the `opts` the
## painter sees. Textures differ by it as by any option.

## Painted textures by their inputs; identical pieces share one texture.
static var _cache: Dictionary = {}
## A texture's emissive pixels by the same key, or null when its painter drew nothing glowing.
static var _emissive: Dictionary = {}
## Painters' looks by their handle (`handle`).
static var _looks: Dictionary = {}
## Guards the caches and `_warmed` while the district's shared textures are painted on a worker.
static var _warm_lock := Mutex.new()
## The cold shared requests the worker paints, each `{ key, request }` (read-only while it runs).
static var _warm_requests: Array = []
## Images the worker has painted, by key; `render_flat` files one as a texture on the main thread
## when its key is asked for, `finish_warming` files the rest.
static var _warmed: Dictionary = {}
## The worker's task id, or -1 when no warm is outstanding.
static var _warm_task := -1


## `painter`'s ALBEDO for a footprint of `size` world px: the 3D render's texture of a piece,
## shaded by the 3D lights. The painter runs on a canvas whose light is `Vector2.ZERO`, so `bevel`,
## `bevel_relative` and `cast_shadows` do nothing and `glare` is skipped; the art stays in the
## painter's canonical frame (no facing turn, no lighting angle), so one texture serves the piece
## whatever way it turns. The surface finishes (grain, speckle, fleck) stay. Cached under the key of
## its inputs plus `|flat`; a `warm` request paints the same. `facing` (a decal's, laid on a floor
## or wall by its own rect) turns the picture in quarter turns: `size` is the footprint as it lies,
## painted canonical (its sides swapped for a sideways facing) and turned.
static func render_flat(painter: Script, size: Vector2, color: Color,
		opts: Dictionary = {}, facing: Vector2 = Vector2.DOWN) -> Texture2D:
	var turns := _turns(facing)
	var key := _flat_key(_key(painter, size, color, opts), turns)
	var cached := _cached(key)
	if cached != null:
		return cached
	return _paint_and_store({
		"painter": painter, "size": size, "color": color, "opts": opts, "facing": facing,
	})


## The emissive twin of `render_flat`'s texture: only what the painter drew `glowing`, in the art's
## colours, transparent elsewhere; null when it drew nothing glowing.
static func emissive_flat(painter: Script, size: Vector2, color: Color,
		opts: Dictionary = {}, facing: Vector2 = Vector2.DOWN) -> Texture2D:
	render_flat(painter, size, color, opts, facing)
	_warm_lock.lock()
	var texture: Texture2D = _emissive.get(
		_flat_key(_key(painter, size, color, opts), _turns(facing)),
	)
	_warm_lock.unlock()
	return texture


## Paint every cold shared request on one worker (as Sound's library warm does). Painters read only
## constant tables and static tuning, so a main-thread paint may overlap it. Cache reads and writes
## are mutexed. A `render_flat` never waits for it: it files the image the worker already painted
## for its key, else paints synchronously, and the worker skips a key that is cached by then. Keys
## and pixels are the synchronous paint's either way.
static func warm(requests: Array) -> void:
	finish_warming()
	_warm_lock.lock()
	var seen := {}
	for request: Dictionary in requests:
		var key := _request_key(request)
		if not _cache.has(key) and not seen.has(key):
			seen[key] = true
			_warm_requests.append({ "key": key, "request": request })
	_warm_lock.unlock()
	if not _warm_requests.is_empty():
		var settled := {}
		for entry: Dictionary in _warm_requests:
			_settle(entry["request"]["painter"], settled)
		_warm_task = WorkerThreadPool.add_task(_warm_all, false, "pixel-art pre-warm")


## Have `script` and every script it preloads compiled, here on the main thread: a constant table
## a main-thread compile is still building (a font's rows) reads as garbage on the worker.
static func _settle(script: Script, settled: Dictionary) -> void:
	if script == null or settled.has(script):
		return
	settled[script] = true
	for value: Variant in script.get_script_constant_map().values():
		if value is Script:
			_settle(value, settled)


## Wait for the outstanding warm to finish and file every image it painted as a texture, on the
## main thread. A build does not need this: it is for a caller that wants the cache complete.
static func finish_warming() -> void:
	if _warm_task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_warm_task)
	_warm_task = -1
	_warm_lock.lock()
	var painted := _warmed
	_warmed = {}
	_warm_requests.clear()
	_warm_lock.unlock()
	for images: Dictionary in painted.values():
		_file_painted(images)


## Paint the cold shared requests in order on the worker, skipping a key a build has cached. Only
## image work runs here: creating an ImageTexture would touch the rendering server off the main
## thread.
static func _warm_all() -> void:
	for entry: Dictionary in _warm_requests:
		var key: String = entry["key"]
		_warm_lock.lock()
		var done := _cache.has(key)
		_warm_lock.unlock()
		if done:
			continue
		var images := _paint_images(entry["request"])
		_warm_lock.lock()
		_warmed[key] = images
		_warm_lock.unlock()


## A cached texture, or the one made from the image the warm already painted for `key`, or null.
## Reads under the warm lock.
static func _cached(key: String) -> Texture2D:
	_warm_lock.lock()
	var texture: Texture2D = _cache.get(key)
	var images: Dictionary = {}
	if texture == null and _warmed.has(key):
		images = _warmed[key]
		_warmed.erase(key)
	_warm_lock.unlock()
	return texture if images.is_empty() else _file_painted(images)


## Paint a cold request, then file its art and emissive textures unless another path got there
## first.
static func _paint_and_store(request: Dictionary) -> Texture2D:
	return _file_painted(_paint_images(request))


## Paint a request into ordinary and emissive Images, with no texture or cache access. Pure image
## work is what the warm's worker runs.
static func _paint_images(request: Dictionary) -> Dictionary:
	var base_key := _key(
		request["painter"], request["size"], request["color"], request["opts"],
	)
	var turns := _turns(request.get("facing", Vector2.DOWN))
	var res := _resolution(request["size"])
	var canon := Vector2i(res.y, res.x) if turns % 2 == 1 else res
	var flat := _paint(
		request["painter"],
		_flat_canvas(canon, base_key),
		request["color"],
		request["opts"],
	)
	var glow := flat.emissive()
	return {
		"key": _flat_key(base_key, turns),
		"image": _turned(flat.img, turns),
		"glow": null if glow == null else _turned(glow, turns),
	}


## File painted Images into the caches on the main thread, or return the entry a synchronous paint
## already filed. `_warm_lock` covers both dictionaries and the duplicate-entry check.
static func _file_painted(images: Dictionary) -> Texture2D:
	var key: String = images["key"]
	_warm_lock.lock()
	if _cache.has(key):
		var cached: Texture2D = _cache[key]
		_warm_lock.unlock()
		return cached
	var glow: Image = images["glow"]
	_emissive[key] = null if glow == null else ImageTexture.create_from_image(glow)
	var texture := _store_unlocked(key, images["image"])
	_warm_lock.unlock()
	return texture


## Clockwise quarter turns taking the canonical front (+y) onto the cardinal `facing`.
static func _turns(facing: Vector2) -> int:
	return posmod(roundi(Vector2.DOWN.angle_to(facing) / (PI * 0.5)), 4)


## The cache key (and `_emissive`'s) for the inputs' `_key` at `turns` quarter turns.
static func _flat_key(base_key: String, turns := 0) -> String:
	return base_key + "|flat" if turns == 0 else "%s|flat|f%d" % [base_key, turns]


## The cache key a warm request will be filed under: `render_flat`'s.
static func _request_key(request: Dictionary) -> String:
	var base_key := _key(request["painter"], request["size"], request["color"], request["opts"])
	return _flat_key(base_key, _turns(request.get("facing", Vector2.DOWN)))


## `img` turned by `turns` clockwise quarter turns.
static func _turned(img: Image, turns: int) -> Image:
	match turns:
		1:
			img.rotate_90(CLOCKWISE)
		2:
			img.rotate_180()
		3:
			img.rotate_90(COUNTERCLOCKWISE)
	return img


## The handle of `look`, registered for `look_of`. A painter's options carry a big look (a character
## style's resolved look, a weapon style's colours) as this int (`opts.look`), never the look
## itself: the caches are keyed by the options and hash them on every call. The
## handle is the look's hash, so the same look always has the same one and a cached texture keyed by
## it is always that look's.
static func handle(look: Dictionary) -> int:
	var id := hash(look)
	_looks[id] = look
	return id


## The look a painter's `opts` name (`opts.look`, a `handle`), or {} for none.
static func look_of(opts: Dictionary) -> Dictionary:
	return _looks.get(opts.get("look", 0), {})


## The art resolution (art px) of a `size` world-px footprint.
static func _resolution(size: Vector2) -> Vector2i:
	return Vector2i((size / maxf(ArtCanvasConfig.pixel_size, 0.01)).round())


## The cache key of a painter's inputs, without orientation: the material (`opts.material`) and
## the painter's own options, as `_paint` hands them over.
static func _key(painter: Script, size: Vector2, color: Color, opts: Dictionary) -> String:
	return ("%s|%v|%s|%s|%s|%s"
			% [
				painter.resource_path,
				size,
				color.to_html(),
				opts.get("material", ""),
				_painter_opts(opts),
				ArtCanvasConfig.pixel_size,
			])


## A fresh canvas of `res` with no light (`render_flat`), seeded by `seed_key`.
static func _flat_canvas(res: Vector2i, seed_key: String) -> PixelCanvas:
	return PixelCanvas.new(res.x, res.y, hash(seed_key), Vector2.ZERO)


## Paint `painter` onto `canvas` (`_canvas`), handing it `opts`' `material` as its own argument and
## the rest as its options; returns the canvas.
static func _paint(painter: Script, canvas: PixelCanvas, color: Color,
		opts: Dictionary) -> PixelCanvas:
	painter.paint(canvas, color, String(opts.get("material", "")), _painter_opts(opts))
	return canvas


## `opts` without its `material` key: the options a painter is handed (`opts` itself when it has
## none, else a copy).
static func _painter_opts(opts: Dictionary) -> Dictionary:
	if not opts.has("material"):
		return opts
	var own := opts.duplicate()
	own.erase("material")
	return own


## Cache `img` as a texture under `key` and return it. `_warm_lock` is held.
static func _store_unlocked(key: String, img: Image) -> Texture2D:
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
