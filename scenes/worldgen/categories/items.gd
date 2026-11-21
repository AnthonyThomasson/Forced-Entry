class_name ItemsCatalog
## World Generation domain: the small items (`docs/stacked-items.md`): tableware,
## books, a desk lamp, a monitor, boxes and crates. Each is a free piece (Objects' `item` painter
## and mesh): it rests on the floor or on a flat top of another piece (`ObjectFactory.spawn_on`,
## interface 2), settles asleep and moves alone. `RoomItems` places them in a house and a district
## tower from the data below (`TOPS`, `TOPS_BY_ART`, `FLOOR`; `docs/stacked-items.md` SI9). The
## cups, plates, bowls and books lie no higher than a step (`DoorFallConfig.step_over`), so a
## walker steps over one on the floor. Sizes are footprints in px (42.3 px a metre); the heights
## are `ObjectMeshItemConfig`'s.

const OBJECTS := {
	"plate": {
		"name": "Plate",
		"shape": "circle",
		"size": Vector2(12, 12),
		"color": Color(0.9, 0.9, 0.86),
		"material": "ceramic",
		"art": "item",
		"art_opts": { "kind": "plate" },
		"weight": 1,
		"penetration": 6,
	},
	"cup": {
		"name": "Cup",
		"shape": "circle",
		"size": Vector2(7, 7),
		"color": Color(0.82, 0.8, 0.74),
		"material": "ceramic",
		"art": "item",
		"art_opts": { "kind": "cup" },
		"weight": 0.5,
		"penetration": 6,
	},
	"bowl": {
		"name": "Bowl",
		"shape": "circle",
		"size": Vector2(10, 10),
		"color": Color(0.84, 0.86, 0.9),
		"material": "ceramic",
		"art": "item",
		"art_opts": { "kind": "bowl" },
		"weight": 0.8,
		"penetration": 6,
	},
	"book": {
		"name": "Book",
		"shape": "rect",
		"size": Vector2(9, 12),
		"color": Color(0.45, 0.2, 0.18),
		"material": "paper",
		"art": "item",
		"art_opts": { "kind": "book" },
		"weight": 0.8,
		"penetration": 12,
	},
	"desk_lamp": {
		"name": "Desk lamp",
		"shape": "circle",
		"size": Vector2(10, 10),
		"color": Color(0.3, 0.32, 0.34),
		"material": "metal",
		"art": "item",
		"art_opts": { "kind": "desk_lamp" },
		"weight": 1.5,
		"penetration": 30,
	},
	"monitor": {
		"name": "Monitor",
		"shape": "rect",
		"size": Vector2(24, 8),
		"color": Color(0.16, 0.17, 0.19),
		"material": "electronics",
		"art": "item",
		"art_opts": { "kind": "monitor" },
		"weight": 3,
		"penetration": 25,
	},
	"box": {
		"name": "Box",
		"shape": "square",
		"size": Vector2(14, 14),
		"color": Color(0.62, 0.48, 0.3),
		"material": "cardboard",
		"art": "item",
		"art_opts": { "kind": "box" },
		"weight": 4,
		"penetration": 25,
	},
	"crate": {
		"name": "Crate",
		"shape": "square",
		"size": Vector2(20, 20),
		"color": Color(0.5, 0.38, 0.24),
		"material": "wood",
		"art": "item",
		"art_opts": { "kind": "crate" },
		"weight": 14,
		"penetration": 70,
	},
}
## What lies on a flat top, by the piece's catalogue key: `[item key, weight]` pairs (`RoomItems`
## draws 1 to `WorldGenItemConfig.top_max` of them on about half the tops). A key here beats
## `TOPS_BY_ART`; an empty list keeps a top bare. A piece that carries its own items (`PieceCarries`:
## a loose shelf, a crate stack, a pallet, a hotplate, and a desk, a nightstand, a counter:
## `HomeItemsCatalog`) has no row: its items are set by `RoomItems.carry`, it takes no random fill.
const TOPS := {
	"table": [["plate", 3.0], ["cup", 3.0], ["bowl", 2.0], ["book", 1.0]],
	"dining_table": [["plate", 4.0], ["cup", 3.0], ["bowl", 2.0]],
	"coffee_table": [["cup", 3.0], ["book", 3.0], ["bowl", 1.0], ["desk_lamp", 0.5]],
	"filing_cabinet": [["box", 3.0], ["book", 2.0]],
	"mirror": [],
	"sink": [],
	"laundry_sink": [],
}
## What lies on a flat top of a piece with no `TOPS` row, by its art id (the general rule: any
## small piece on any flat top). A counter with a basin is no flat top.
const TOPS_BY_ART := {
	"table": [["cup", 3.0], ["book", 3.0], ["plate", 2.0]],
	"counter": [["plate", 3.0], ["cup", 3.0], ["bowl", 2.0]],
	"cabinet": [["book", 2.0], ["desk_lamp", 2.0], ["cup", 1.0]],
}
## The kinds that go on each other in a stack on a top (a book on a book, a plate on a plate).
const STACKS_ON_TOPS := ["plate", "book"]
## The floor stacks of boxes and crates a room type gets (`RoomItems`): `chance` a room has any,
## `count` the stacks (inclusive range), `high` how many items each (inclusive), `base` what the
## bottom one is, `top` what goes on it (`[key, weight]` pairs).
## A stockroom has none: its crate stacks and pallets are places that carry loose crates, a pallet
## and wrapped boxes (`StockroomCatalog`, decision D21), so its floor is not strewn twice.
const FLOOR := {
	"garage": {
		"chance": 0.8, "count": Vector2i(1, 2), "high": Vector2i(2, 3),
		"base": [["crate", 2.0], ["box", 3.0]], "top": [["box", 3.0]],
	},
	"home_office": {
		"chance": 0.6, "count": Vector2i(1, 2), "high": Vector2i(2, 3),
		"base": [["box", 3.0]], "top": [["box", 3.0]],
	},
	"laundry_room": {
		"chance": 0.4, "count": Vector2i(1, 1), "high": Vector2i(2, 2),
		"base": [["box", 3.0]], "top": [["box", 3.0]],
	},
}


## The `[key, weight]` options for items on the top of the piece `key` (catalogue `definition`):
## its `TOPS` row, else its art's `TOPS_BY_ART` row; `[]` when it has no flat top to speak of (a
## basin, a mat, a floor piece that is not solid, an unknown art).
static func options_for(key: String, definition: Dictionary) -> Array:
	if not definition.get("solid", true) or definition.get("ground", false):
		return []
	if PieceCarries.carries(definition):
		return []  # An emptied piece has its own items (`RoomItems.carry`): no fill at random.
	if TOPS.has(key):
		return TOPS[key]
	var opts: Variant = definition.get("art_opts", {})
	if opts is Dictionary and (opts as Dictionary).has("basin"):
		return []
	return TOPS_BY_ART.get(definition.get("art", ""), [])


## The `[key, weight]` pairs of `options` whose footprint fits inside one of size `under` (px): an
## item goes only on one at least as big as it, so a crate stands on a crate, a box on a box or a
## crate, and never a crate on a box (it would overhang and topple).
static func fitting(options: Array, under: Vector2) -> Array:
	return options.filter(
		func(option: Array) -> bool:
			var size: Vector2 = OBJECTS[option[0]]["size"]
			return size.x <= under.x and size.y <= under.y
	)
