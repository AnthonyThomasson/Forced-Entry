class_name BodyDrawCache extends RefCounted

## `render_turned` slots (`slot`): the standing body's shoulders, head and fists, the laid-out
## body's head and fists, a trunk face by its kind, then a limb segment by chain and place.
const SHOULDERS := 0
const HEAD := 1
const HAND := 2  # + the hand's side, 0 or 1
const LAID_HEAD := 4
const LAID_HAND := 5  # + the hand's side
const TRUNK_FACE := { "top": 8, "front": 9, "back": 10, "side": 11 }
const SEGMENT := 16  # + 8 per chain (the legs, the arms, the neck) + the segment's place
const NECK := 4
## Most uv sets kept before they start over (a turning part asks for many angles).
const UVS_MAX := 512

## What the body's draw keeps from one draw to the next so an unchanged part costs a lookup, not a
## rebuild (`character_visuals.gd`, `body_limbs.gd`, `body_shadow.gd`): the last texture each part
## asked `PixelArt.render_turned` for, the silhouette and uvs of a part no shot has dented, and one
## reused `FillBatch`. Every drawn pixel equals the uncached draw's: a dent, an outfit, a held item
## or a pose change asks for something else and gets it. `enabled` false is the plain path, which
## `tests/character/draw_cache_pixel_identical_test.gd` compares the cached draw against.

## Whether the draw uses its caches (a test switches it off to draw plainly).
static var enabled := true
## How many shape lookups the caches answered (a test reads it).
static var shape_hits := 0
## How many `FillBatch`es `batch` made (a test reads it).
static var batches_made := 0

## The silhouette of an undented round part by its size and the ring's point count.
var _polygons := {}
## The uvs of an undented round part by its size, then the angle its art is turned by.
var _uvs := {}
## How many uv sets `_uvs` holds.
var _uv_count := 0
## The `render_turned` slots handed out, by id.
var _slots := {}
## The `FillBatch` kept for each canvas item (`batch`).
var _batches := {}
## The slot of the uncached draw.
var plain := PixelArt.TurnedLast.new()
## How the round part being drawn is drawn: one look, refilled for each part
## (`visuals._round_look`).
var look := ShapeLook.new()
## Whether a draw records each round part's silhouette and uvs in `shapes` (a test reads them:
## headless nothing is rendered to compare).
var record := false
## The silhouette and uvs of each round part the last draw drew, in order (`record`).
var shapes: Array[Dictionary] = []


func _init() -> void:
	plain.plain = true


## The slot of part `id`: `slot(id).render(...)` is `PixelArt.render_turned` answered from the
## part's last call, or plain while the caches are off.
func slot(id: int) -> PixelArt.TurnedLast:
	if not enabled:
		return plain
	var kept: PixelArt.TurnedLast = _slots.get(id)
	if kept == null:
		kept = PixelArt.TurnedLast.new()
		_slots[id] = kept
	return kept


## `Deformation.drawable_polygon("circle", size, impacts)`: for a part no shot has dented the one
## silhouette its size draws, kept. Any dent asks Deformation afresh.
func polygon(size: Vector2, impacts: Array) -> PackedVector2Array:
	if not enabled or not impacts.is_empty():
		return Deformation.drawable_polygon("circle", size, impacts)
	var key := Vector3(size.x, size.y, PhysicsDeformConfig.circle_points)
	var kept: Variant = _polygons.get(key)
	if kept == null:
		kept = Deformation.drawable_polygon("circle", size, impacts)
		_polygons[key] = kept
	else:
		shape_hits += 1
	return kept


## `Deformation.texture_uvs(poly, size, angle)` for `poly` from `polygon(size, impacts)`: for an
## undented part kept by its size and angle (the silhouette is the same one).
func uvs(
	poly: PackedVector2Array,
	size: Vector2,
	impacts: Array,
	angle: float,
) -> PackedVector2Array:
	if not enabled or not impacts.is_empty():
		return Deformation.texture_uvs(poly, size, angle)
	# By size, then by the exact angle (a Vector3 key would hold it as a float32).
	var by_angle: Dictionary = _uvs.get(size, {})
	var kept: Variant = by_angle.get(angle)
	if kept == null:
		if _uv_count >= UVS_MAX:
			_uvs.clear()
			_uv_count = 0
			by_angle = {}
		kept = Deformation.texture_uvs(poly, size, angle)
		by_angle[angle] = kept
		_uvs[size] = by_angle
		_uv_count += 1
	else:
		shape_hits += 1
	return kept


## A `FillBatch` for `canvas` (the visuals or their shadow node): the one kept for it while the
## caches are on (a batch is empty again after each `flush`, and every draw flushes what it adds),
## else a new one.
func batch(canvas: CanvasItem) -> FillBatch:
	var kept: FillBatch = _batches.get(canvas) if enabled else null
	if kept == null:
		kept = FillBatch.new(canvas)
		batches_made += 1
		if enabled:
			_batches[canvas] = kept
	return kept
