class_name ShopHollow
extends RefCounted
## Objects domain, the hollow shop pieces (`docs/stacked-items.md` SI16, decision D21): the drinks
## fridge, the snack machine and the shelf aisle are thin parts round empty bays, not a solid
## block with the stock painted on: the bottles, snack packs and goods stand on their boards as free
## items (`ShopStock`, `PieceCarries`). A fridge and a snack machine have a glass front (a part with
## `material: "glass"`: a round meets it as glass, `Piece.get_surface_at`) that holds the stock in;
## it is a collider and is not drawn (a clear pane has no mesh). The piece moves as the solid box of
## its extent (`PieceBody._as_solid`).
## Everything is in px in the painter's canonical frame (`FurnitureSpec.area`: back-left corner at
## (0, 0), x across, the front toward +y); `parts` are `{ base, top, rect[, material] }` as
## `PieceHeights` reads them, `bays` the open spaces the stock stands in.

const ShopMesh = preload("res://scenes/objects/art/shop_mesh.gd")
const KINDS := ["fridge", "snack", "aisle"]
## Thickness of a side and the back, as bodies (thicker than drawn: `ShelfMesh.HULL`'s reason), of
## the glass front, and of a board; the fridge's kick plate; the snack machine's window band and
## its keypad column.
const WALL := 4.0
const GLASS := 3.0
const BOARD := 2.0
const KICK := 6.0
const SNACK_SILL := 8.0
const SNACK_WINDOW := 34.0
const KEYPAD := 12.0
## The aisle: the boards' spacing and the lip along each outer edge.
const TIER_GAP := 18.0
const LIP := 2.0


## Whether `spec` is a shop piece that is hollow: a fridge, a snack machine or an aisle.
static func has(spec: FurnitureSpec) -> bool:
	return spec.art == "shop" and ShopMesh.kind_of(spec) in KINDS


## The parts of `spec` (`has`), lowest first: sides, back, roof or lip, boards, the glass.
static func parts(spec: FurnitureSpec) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var h := ShopMesh.height_of(spec)
	var w := spec.size.x
	var d := spec.size.y
	match ShopMesh.kind_of(spec):
		"fridge":
			_add(spec, out, Rect2(0, 0, w, d), 0.0, KICK)
			_add(spec, out, Rect2(0, 0, WALL, d), KICK, h - 3.0)
			_add(spec, out, Rect2(w - WALL, 0, WALL, d), KICK, h - 3.0)
			_add(spec, out, Rect2(WALL, 0, w - 2.0 * WALL, WALL), KICK, h - 3.0)
			_add(spec, out, Rect2(0, 0, w, d), h - 3.0, h)
			_add(spec, out, Rect2(WALL, d - GLASS, w - 2.0 * WALL, GLASS), h - 8.0, h - 3.0)
			_add_glass(spec, out, Rect2(WALL, d - GLASS, w - 2.0 * WALL, GLASS), KICK, h - 8.0)
		"snack":
			var top := SNACK_SILL + SNACK_WINDOW
			_add(spec, out, Rect2(0, 0, w, d), 0.0, SNACK_SILL)
			_add(spec, out, Rect2(0, 0, WALL, d), SNACK_SILL, top)
			_add(spec, out, Rect2(w - KEYPAD, 0, KEYPAD, d), SNACK_SILL, top)
			_add(spec, out, Rect2(WALL, 0, w - WALL - KEYPAD, WALL), SNACK_SILL, top)
			_add(spec, out, Rect2(0, 0, w, d), top, h)
			_add_glass(
				spec, out, Rect2(WALL, d - GLASS, w - WALL - KEYPAD, GLASS), SNACK_SILL, top
			)
		_:
			var middle := floorf(d / 2.0)
			_add(spec, out, Rect2(0, 0, WALL, d), 0.0, h)
			_add(spec, out, Rect2(w - WALL, 0, WALL, d), 0.0, h)
			_add(spec, out, Rect2(WALL, middle - WALL * 0.5, w - 2.0 * WALL, WALL), 0.0, h)
			_add(spec, out, Rect2(WALL, 0, w - 2.0 * WALL, LIP), h - LIP, h)
			_add(spec, out, Rect2(WALL, d - LIP, w - 2.0 * WALL, LIP), h - LIP, h)
	for bay in bays(spec):
		for top: float in bay["tops"]:
			_add(spec, out, bay["area"], top - BOARD, top)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["base"] < b["base"])
	return out


## The glass of `spec` as `parts` entries (none for an aisle).
static func glass(spec: FurnitureSpec) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part: Dictionary in parts(spec):
		if part.get("material", "") == "glass":
			out.append(part)
	return out


## The surface of `spec`'s glass a round meets at `point` (px in the canonical frame from the
## back-left corner), `height` px up: the glass's `{ penetration, material, color }` when the point
## is on a glass part, `{}` otherwise (the steel's).
static func surface_at(spec: FurnitureSpec, height: float, point: Vector2) -> Dictionary:
	if not has(spec):
		return {}
	for part: Dictionary in glass(spec):
		var rect: Rect2 = part["rect"]
		var area := Rect2(rect.position * spec.size, rect.size * spec.size).grow(1.0)
		if height >= part["base"] and height <= part["top"] and area.has_point(point):
			return {
				"penetration": ObjectMeshShopConfig.glass_penetration,
				"material": "glass",
				"color": ObjectArtShopConfig.shop_glass_color,
			}
	return {}


## The bays of `spec`: `{ area (px), tops (px above the floor the boards' tops are at), room (px of
## height above a board), depth (px) the stock stands in, key (the stock's item) }`.
static func bays(spec: FurnitureSpec) -> Array[Dictionary]:
	var w := spec.size.x
	var d := spec.size.y
	match ShopMesh.kind_of(spec):
		"fridge":
			var shelves: Array[float] = [KICK + BOARD]
			while shelves.size() < 3:
				shelves.append(shelves[-1] + 22.0)
			return [{
				"area": Rect2(WALL, WALL, w - 2.0 * WALL, d - WALL - GLASS), "tops": shelves,
				"room": 20.0, "depth": 8.0, "key": "bottles",
			}]
		"snack":
			var shelves: Array[float] = [SNACK_SILL + BOARD, SNACK_SILL + 14.0 + BOARD]
			return [{
				"area": Rect2(WALL, WALL, w - WALL - KEYPAD, d - WALL - GLASS), "tops": shelves,
				"room": 12.0, "depth": 6.0, "key": "snacks",
			}]
	var middle := floorf(d / 2.0)
	var tops: Array[float] = []
	for k in maxi(1, ObjectMeshShopConfig.aisle_tiers):
		tops.append(BOARD + k * TIER_GAP)
	var run := middle - WALL * 0.5 - LIP
	return [
		{
			"area": Rect2(WALL, LIP, w - 2.0 * WALL, run), "tops": tops, "room": 14.0,
			"depth": 6.0, "key": "snacks",
		},
		{
			"area": Rect2(WALL, middle + WALL * 0.5, w - 2.0 * WALL, run), "tops": tops,
			"room": 14.0, "depth": 6.0, "key": "snacks",
		},
	]


## One part over `area` (px), `base` to `top`.
static func _add(
	spec: FurnitureSpec,
	out: Array[Dictionary],
	area: Rect2,
	base: float,
	top: float,
) -> void:
	var size := Vector2(maxf(spec.size.x, 1.0), maxf(spec.size.y, 1.0))
	var part := { "base": base, "top": top, "rect": Rect2(area.position / size, area.size / size) }
	out.append(part)


## A glass part over `area` (px), `base` to `top`: what a round meets as glass.
static func _add_glass(
	spec: FurnitureSpec, out: Array[Dictionary], area: Rect2, base: float, top: float
) -> void:
	_add(spec, out, area, base, top)
	out[-1]["material"] = "glass"
