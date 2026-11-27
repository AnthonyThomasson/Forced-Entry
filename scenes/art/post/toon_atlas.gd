class_name ToonAtlas
extends RefCounted
## Art domain, the pixel post: the painted textures of the textured toon packed into the layers of
## ONE `Texture2DArray`, so that meshes of different textures share a material and the engine draws
## those that share a mesh in one call. A texture is copied once, the first time a node shows it
## (`slot`), into a page of `PixelPostConfig.atlas_page` texels a side (rows of shelves); the
## shader reads it by texel (`toon_tex.gdshader`, the instance uniform `atlas_rect`), so a pixel is
## the texel it was on a texture of its own and no neighbour bleeds in. A texture is therefore
## never updated in place after a node showed it. The atlas holds no texture alive: the nodes
## showing one do (`MeshNodes.textured`), and the place of a freed one is given to the next texture
## of its size. Pages are written to the GPU once a frame, before it is drawn (`flush`). A copy is a
## readback and a write of the page, so what is first shown mid-match is copied at match build
## (`MeshNodes.warm_textured`), and the array is made with a spare `GROW` of layers (`reserve`): a
## page opened later writes that page alone, not the array, until the spare is used up.

## The layers `slot` packs a page index into `atlas_rect.x` with: above any page's side.
const LAYER_STEP := 4096
## The layers the array grows by, and the least it is made with beyond the pages in use.
const GROW := 8

## The array every atlased material samples.
static var _array := Texture2DArray.new()
## The pages' pixels, one `Image` a layer, kept to write a layer again.
static var _pages: Array[Image] = []
## The shelves of each page: `[y, height, next free x]` each, filled left to right.
static var _shelves: Array = []
## Where each texture lies, by instance id: `{ ref: WeakRef, rect: Vector4, size: Vector2i }`.
static var _slots: Dictionary = {}
## The places of freed textures, by size: `Array` of `[page, Vector2i]`.
static var _free: Dictionary = {}
## The pages written since the last `flush`, the layers the array has and those `reserve` asked for.
static var _dirty: Dictionary = {}
static var _layers := 0
static var _wanted := 0
static var _hooked := false
## The size at which the next new texture first forgets the freed ones.
static var _prune_at := 64


## The array the atlased materials sample (empty until the first `slot`).
static func array() -> Texture2DArray:
	return _array


## Whether `texture` fits a page (a larger one keeps a texture and material of its own).
static func fits(texture: Texture2D) -> bool:
	var side := PixelPostConfig.atlas_page
	return texture.get_width() <= side and texture.get_height() <= side


## Where `texture` lies, for the instance uniform `atlas_rect`: x its left texel plus
## `LAYER_STEP` times its layer, y its top texel, z its width, w its height. Copied in the first
## time it is asked for.
static func slot(texture: Texture2D) -> Vector4:
	var id := texture.get_instance_id()
	var held: Variant = _slots.get(id)
	if held != null and (held["ref"] as WeakRef).get_ref() == texture:
		return held["rect"]
	if _slots.size() >= _prune_at:
		forget_freed()
		_prune_at = maxi(64, _slots.size() * 2)
	var size := Vector2i(texture.get_width(), texture.get_height())
	var place := _place(size)
	var page: int = place[0]
	var at: Vector2i = place[1]
	var image := texture.get_image()
	if image.get_format() != Image.FORMAT_RGBA8 or image.has_mipmaps():
		image = image.duplicate()
		image.clear_mipmaps()
		image.convert(Image.FORMAT_RGBA8)
	_pages[page].blit_rect(image, Rect2i(Vector2i.ZERO, size), at)
	_dirty[page] = true
	var rect := Vector4(at.x + LAYER_STEP * page, at.y, size.x, size.y)
	_slots[id] = { "ref": weakref(texture), "rect": rect, "page": page, "at": at }
	_hook()
	return rect


## Whether the atlas holds `texture` (a test reads it).
static func holds(texture: Texture2D) -> bool:
	var held: Variant = _slots.get(texture.get_instance_id())
	return held != null and (held["ref"] as WeakRef).get_ref() == texture


## The pages in use; the array holds as many layers or more (a test reads it).
static func pages_used() -> int:
	return _pages.size()


## The pages the last `reserve` asked the array to hold (a test reads it).
static func pages_reserved() -> int:
	return _wanted


## Have the array hold at least `GROW` pages beyond those in use from the next `flush` on (asked
## once a match's meshes are built).
static func reserve() -> void:
	_wanted = _pages.size() + GROW
	_hook()


## How many textures the atlas holds that are still alive.
static func count() -> int:
	forget_freed()
	return _slots.size()


## The texels the array holds where `rect` (a `slot`) lies, as the GPU is given them (a test).
static func pixels(rect: Vector4) -> Image:
	var page := floori(rect.x / LAYER_STEP)
	var at := Vector2i(int(rect.x) - page * LAYER_STEP, int(rect.y))
	return _pages[page].get_region(Rect2i(at, Vector2i(int(rect.z), int(rect.w))))


## Write the pages changed since the last call to the array: the whole array again when it has to
## grow (more pages, or more `reserve` asked for), else the changed layers. Connected to
## `RenderingServer.frame_pre_draw`.
static func flush() -> void:
	var wanted := maxi(_pages.size(), _wanted)
	if _dirty.is_empty() and wanted <= _layers:
		return
	if wanted > _layers:
		_layers = ceili(wanted / float(GROW)) * GROW
		var images: Array[Image] = _pages.duplicate()
		while images.size() < _layers:
			images.append(_blank())
		_array.create_from_images(images)
	else:
		for page: int in _dirty:
			_array.update_layer(_pages[page], page)
	_dirty.clear()


## Give the places of textures nothing holds any more to the free list.
static func forget_freed() -> void:
	for id: int in _slots.keys():
		var held: Dictionary = _slots[id]
		if (held["ref"] as WeakRef).get_ref() != null:
			continue
		var rect: Vector4 = held["rect"]
		var size := Vector2i(int(rect.z), int(rect.w))
		if not _free.has(size):
			_free[size] = []
		_free[size].append([held["page"], held["at"]])
		_slots.erase(id)


## A free `[page, texel]` for `size`: a freed texture's of the same size, else the end of the
## shortest shelf it fits, else a new shelf, else a new page.
static func _place(size: Vector2i) -> Array:
	var free: Array = _free.get(size, [])
	if not free.is_empty():
		return free.pop_back()
	var side := PixelPostConfig.atlas_page
	var best: Array = []
	var best_page := -1
	for page in _pages.size():
		for shelf: Array in _shelves[page]:
			if shelf[1] < size.y or side - int(shelf[2]) < size.x:
				continue
			if best.is_empty() or shelf[1] < best[1]:
				best = shelf
				best_page = page
	# A shelf far taller than the texture wastes its rows: open one of its own height instead.
	if best.is_empty() or best[1] > size.y * 1.5:
		for page in _pages.size():
			var top := 0
			for shelf: Array in _shelves[page]:
				top = maxi(top, int(shelf[0]) + int(shelf[1]))
			if side - top >= size.y:
				_shelves[page].append([top, size.y, size.x])
				return [page, Vector2i(0, top)]
	if not best.is_empty():
		var at := Vector2i(best[2], best[0])
		best[2] += size.x
		return [best_page, at]
	_pages.append(_blank())
	_shelves.append([[0, size.y, size.x]])
	return [_pages.size() - 1, Vector2i.ZERO]


## An empty page.
static func _blank() -> Image:
	var side := PixelPostConfig.atlas_page
	return Image.create(side, side, false, Image.FORMAT_RGBA8)


## Write the pages before each frame is drawn from the first texture or `reserve` on.
static func _hook() -> void:
	if _hooked:
		return
	_hooked = true
	RenderingServer.frame_pre_draw.connect(ToonAtlas.flush)
