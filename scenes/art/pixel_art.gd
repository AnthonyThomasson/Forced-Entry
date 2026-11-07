class_name PixelArt
## Renders painters into cached pixel-art textures (Art domain: the entry point the Objects,
## Character, Items and Vehicles domains paint through). A PAINTER is any script with
## `static func paint(canvas: PixelCanvas, base: Color, material: String, opts: Dictionary)` that
## draws in a canonical frame — front toward +y, width across the front — under `canvas.light`,
## the world light already turned into that frame. Two ways to orient the result:
##   • render(): `facing` is a cardinal direction and the image itself is turned to it (furniture).
##   • render_turned(): the image stays canonical but is lit as if turned by `angle`; the caller
##     draws it rotated by that angle (freely turning things: characters, held items, vehicles).
## Either way the lighting stays consistent in the world. Textures are cached by their inputs
## (static, so they survive scene reloads); a piece's random detail is seeded by its inputs minus
## its orientation, so it doesn't change as the piece turns.
## What a painter draws `glowing` (PixelCanvas: a screen's face, a tube, a bulb) is kept for a
## `render`ed piece as a second, EMISSIVE texture of only those pixels (`emissive()`), from the same
## paint, for callers that draw light sources unshaded.
## Every entry point takes the painter's `opts`, which it hands the painter as they are, but for one
## key of its own: `material` (String, default ""), the `material` the painter's `paint` is given
## (the surface finish its tones are drawn in: "fabric", "metal", ...), taken off the `opts` the
## painter sees. Textures differ by it as by any option.

## Most `render_turned` calls remembered by their exact arguments (see `_turned_memo`) before the
## memo is dropped and refills.
const TURNED_MEMO_MAX := 4096

## How many `render_turned` calls a caller's `TurnedLast` answered (a test reads it).
static var last_hits := 0
## Painted textures by their inputs; identical pieces share one texture.
static var _cache: Dictionary = {}
## A `render`ed texture's emissive pixels by the same key, or null when its painter drew nothing
## glowing.
static var _emissive: Dictionary = {}
## `render_turned`'s textures by the arguments of the calls that fetched them, so a repeat call with
## the same values (a character repaints its parts every frame) is one lookup instead of building
## the key string below. Only a shortcut to `_cache`: which texture a call gets is still decided by
## the string key, so values that key treats as equal still share one texture. Bounded, so arguments
## that never repeat exactly cannot grow it.
static var _turned_memo: Dictionary = {}
## Painters' looks by their handle (`handle`).
static var _looks: Dictionary = {}
## Guards the caches and `_warmed` while the district's shared textures are painted on a worker.
static var _warm_lock := Mutex.new()
## The cold shared requests the worker paints, each `{ key, request }` (read-only while it runs).
static var _warm_requests: Array = []
## Images the worker has painted, by render key; `render` files one as a texture on the main thread
## when its key is asked for, `finish_warming` files the rest.
static var _warmed: Dictionary = {}
## The worker's task id, or -1 when no warm is outstanding.
static var _warm_task := -1


## `painter`'s art for a footprint of `size` world px whose front faces the cardinal `facing`, with
## `opts` (its `material` key PixelArt's own, above).
static func render(painter: Script, size: Vector2, color: Color, facing: Vector2 = Vector2.DOWN,
		opts: Dictionary = {}) -> Texture2D:
	var turns := _turns(facing)
	var base_key := _key(painter, size, color, opts)
	var key := _render_key(base_key, turns)
	var cached := _cached(key)
	if cached != null:
		return cached
	return _paint_and_store({
		"painter": painter, "size": size, "color": color, "facing": facing, "opts": opts,
	})


## Paint every cold shared request on one worker (as Sound's library warm does). Painters read only
## constant tables and static tuning, so a main-thread paint may overlap it. Cache reads and writes
## are mutexed. A `render` never waits for it: it files the image the worker already painted for its
## key, else paints synchronously, and the worker skips a key that is cached by then. Keys and
## pixels are
## the synchronous paint's either way.
static func warm(requests: Array) -> void:
	finish_warming()
	_warm_lock.lock()
	var seen := {}
	for request: Dictionary in requests:
		var key := _render_key(
			_key(request["painter"], request["size"], request["color"], request["opts"]),
			_turns(request["facing"]),
		)
		if not _cache.has(key) and not seen.has(key):
			seen[key] = true
			_warm_requests.append({ "key": key, "request": request })
	_warm_lock.unlock()
	if not _warm_requests.is_empty():
		_warm_task = WorkerThreadPool.add_task(_warm_all, false, "pixel-art pre-warm")


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
	var turns := _turns(request["facing"])
	var base_key := _key(
		request["painter"], request["size"], request["color"], request["opts"],
	)
	var res := _resolution(request["size"])
	var canon := Vector2i(res.y, res.x) if turns % 2 == 1 else res
	var canvas := _paint(
		request["painter"],
		_canvas(canon, -turns * PI * 0.5, base_key),
		request["color"],
		request["opts"],
	)
	var glow := canvas.emissive()
	return {
		"key": _render_key(base_key, turns),
		"image": _turned(canvas.img, turns),
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


## The emissive pixels of `render`'s texture for the same inputs (painting it if it is not cached
## yet): what the painter drew `glowing`, in the art's own colours, transparent elsewhere, the same
## size and orientation; null when it drew nothing glowing.
static func emissive(painter: Script, size: Vector2, color: Color, facing: Vector2 = Vector2.DOWN,
		opts: Dictionary = {}) -> Texture2D:
	render(painter, size, color, facing, opts)
	_warm_lock.lock()
	var texture: Texture2D = _emissive.get(
		_render_key(_key(painter, size, color, opts), _turns(facing)),
	)
	_warm_lock.unlock()
	return texture


## Which way, away from the light, a cast shadow falls in `node`'s frame (a unit vector): the
## world's `ArtCanvasConfig.light_from` reversed, turned into the node's own axes.
static func away_from_light(node: Node2D) -> Vector2:
	var toward := -ArtCanvasConfig.light_from.normalized()
	return node.global_transform.basis_xform_inv(toward).normalized()


## Clockwise quarter turns taking the canonical front (+y) onto the cardinal `facing`.
static func _turns(facing: Vector2) -> int:
	return posmod(roundi(Vector2.DOWN.angle_to(facing) / (PI * 0.5)), 4)


## `render`'s cache key (and `_emissive`'s) for the inputs' `_key` at `turns` quarter turns.
static func _render_key(base_key: String, turns: int) -> String:
	return "%s|f%d" % [base_key, turns]


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


## `painter`'s art for a footprint of `size` world px in its canonical frame, lit as it will look
## once drawn rotated by `angle` (radians, clockwise on screen), with `opts` (its `material` key
## PixelArt's own, above). Callers snap `angle` to a few steps so the cache stays small.
static func render_turned(painter: Script, size: Vector2, color: Color, angle: float,
		opts: Dictionary = {}) -> Texture2D:
	var memo_key: Array = [painter, size, color, opts, ArtCanvasConfig.pixel_size, angle]
	var memo: Variant = _turned_memo.get(memo_key)
	if memo != null:
		return memo
	var base_key := _key(painter, size, color, opts)
	var key := "%s|a%.4f" % [base_key, angle]
	var tex := _cached(key)
	if tex == null:
		var canvas := _canvas(_resolution(size), -angle, base_key)
		_warm_lock.lock()
		tex = _cache.get(key)
		if tex == null:
			tex = _store_unlocked(key, _paint(painter, canvas, color, opts).img)
		_warm_lock.unlock()
	if _turned_memo.size() >= TURNED_MEMO_MAX:
		_turned_memo.clear()
	# The caller may change its dictionary later; the memo keeps the values it was asked with.
	memo_key[3] = opts.duplicate(true)
	_turned_memo[memo_key] = tex
	return tex


## The handle of `look`, registered for `look_of`. A painter's options carry a big look (a character
## style's resolved look, a weapon style's colours) as this int (`opts.look`), never the look
## itself: the caches are keyed by the options and `render_turned` hashes them on every call. The
## handle is the look's hash, so the same look always has the same one and a cached texture keyed by
## it is always that look's.
static func handle(look: Dictionary) -> int:
	var id := hash(look)
	_looks[id] = look
	return id


## The look a painter's `opts` name (`opts.look`, a `handle`), or {} for none.
static func look_of(opts: Dictionary) -> Dictionary:
	return _looks.get(opts.get("look", 0), {})


## `angle` snapped to the nearest of ArtCanvasConfig.turn_steps lighting steps (pass it to
## render_turned, then draw rotated by the exact angle).
static func snap_angle(angle: float) -> float:
	var step := TAU / maxi(1, ArtCanvasConfig.turn_steps)
	return wrapf(roundf(angle / step) * step, 0.0, TAU)


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


## A fresh canvas of `res` seeded by `seed_key`, with the world light turned by `light_turn`.
static func _canvas(res: Vector2i, light_turn: float, seed_key: String) -> PixelCanvas:
	return PixelCanvas.new(
		res.x,
		res.y,
		hash(seed_key),
		ArtCanvasConfig.light_from.rotated(light_turn),
	)


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


## The arguments of one caller's last `render_turned` call and the texture they got (`render`): a
## character draws the same part every frame, so the next call is most often a compare of a few
## values instead of a hashed memo key. Owned by the caller, one per part.
class TurnedLast extends RefCounted:
	## The last call's arguments.
	var painter: Script
	var size := Vector2.ZERO
	var color := Color.BLACK
	var angle := 0.0
	var opts: Dictionary = {}
	var pixel_size := 0.0
	## The texture those arguments got.
	var texture: Texture2D
	## A plain slot never remembers: its `render` is `render_turned` itself (the uncached draw).
	var plain := false


	## `render_turned` of these arguments: this slot's texture when they are the ones it saw last,
	## else the fetched one, remembered.
	func render(p: Script, s: Vector2, c: Color, a: float, o: Dictionary = {}) -> Texture2D:
		if plain:
			return PixelArt.render_turned(p, s, c, a, o)
		if (texture != null and painter == p and angle == a and size == s and color == c
				and pixel_size == ArtCanvasConfig.pixel_size and opts == o):
			PixelArt.last_hits += 1
			return texture
		texture = PixelArt.render_turned(p, s, c, a, o)
		painter = p
		size = s
		color = c
		angle = a
		opts = o.duplicate(true)
		pixel_size = ArtCanvasConfig.pixel_size
		return texture
