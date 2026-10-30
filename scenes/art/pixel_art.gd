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


## `painter`'s art for a footprint of `size` world px whose front faces the cardinal `facing`, with
## `opts` (its `material` key PixelArt's own, above).
static func render(painter: Script, size: Vector2, color: Color, facing: Vector2 = Vector2.DOWN,
		opts: Dictionary = {}) -> Texture2D:
	var turns := _turns(facing)
	var base_key := _key(painter, size, color, opts)
	var key := _render_key(base_key, turns)
	if _cache.has(key):
		return _cache[key]
	var res := _resolution(size)
	var canon := Vector2i(res.y, res.x) if turns % 2 == 1 else res
	var canvas := _paint(painter, _canvas(canon, -turns * PI * 0.5, base_key), color, opts)
	var glow := canvas.emissive()
	_emissive[key] = null if glow == null else ImageTexture.create_from_image(_turned(glow, turns))
	return _store(key, _turned(canvas.img, turns))


## The emissive pixels of `render`'s texture for the same inputs (painting it if it is not cached
## yet): what the painter drew `glowing`, in the art's own colours, transparent elsewhere, the same
## size and orientation; null when it drew nothing glowing.
static func emissive(painter: Script, size: Vector2, color: Color, facing: Vector2 = Vector2.DOWN,
		opts: Dictionary = {}) -> Texture2D:
	render(painter, size, color, facing, opts)
	return _emissive.get(_render_key(_key(painter, size, color, opts), _turns(facing)))


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
	var tex: Texture2D
	if _cache.has(key):
		tex = _cache[key]
	else:
		var canvas := _canvas(_resolution(size), -angle, base_key)
		tex = _store(key, _paint(painter, canvas, color, opts).img)
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


## Cache `img` as a texture under `key` and return it.
static func _store(key: String, img: Image) -> Texture2D:
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
