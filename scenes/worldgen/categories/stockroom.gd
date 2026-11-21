class_name StockroomCatalog
## World Generation domain: stockroom objects, arrangements and recipe: the back room of a shop or
## noodle bar. Stacked crates, a pallet of wrapped boxes and a wall safe (Objects' `stock`
## painter). Shared clutter (cardboard, trash) lives in GeneralCatalog.
## The crates and the pallet are no piece of furniture (decision D21, `docs/stacked-items.md`
## SI13): `crate_stack` and `wrapped_pallet` are bare places (non-solid, no art) that carry loose
## items where the old stack and pallet drew theirs (`carries`: the crates of `ItemsCatalog` and the
## pallet and wrapped boxes of `LooseStockCatalog`; `at` from the place's centre, `lift` the height
## it stands on, px).

const OBJECTS := {
	"crate_stack": {
		"name": "Crates",
		"shape": "rect",
		"size": Vector2(46, 46),
		"color": Color(0.5, 0.38, 0.24),
		"solid": false,
		"material": "wood",
		"carries": [
			{
				"key": "crate", "at": Vector2(-4, 4), "size": Vector2(38, 38), "lift": 0.0,
				"height": 20.0, "weight": 40.0,
			},
			{
				"key": "crate", "at": Vector2(4, -4), "size": Vector2(38, 38), "lift": 20.0,
				"height": 20.0, "weight": 40.0,
			},
		],
	},
	"wrapped_pallet": {
		"name": "Pallet",
		"shape": "rect",
		"size": Vector2(64, 56),
		"color": Color(0.5, 0.38, 0.24),
		"solid": false,
		"material": "wood",
		"carries": [
			{ "key": "pallet", "at": Vector2(0, 0), "size": Vector2(64, 56), "lift": 0.0 },
			{ "key": "wrapped_box", "at": Vector2(-16, -15), "size": Vector2(28, 22), "lift": 5.0 },
			{ "key": "wrapped_box", "at": Vector2(16, -15), "size": Vector2(28, 22), "lift": 5.0 },
			{ "key": "wrapped_box", "at": Vector2(-16, 15), "size": Vector2(28, 22), "lift": 5.0 },
			{ "key": "wrapped_box", "at": Vector2(16, 15), "size": Vector2(28, 22), "lift": 5.0 },
		],
	},
	"wall_safe": {
		"name": "Safe",
		"shape": "rect",
		"size": Vector2(36, 32),
		"color": Color(0.4, 0.41, 0.4),
		"material": "metal",
		"art": "stock",
		"art_opts": { "kind": "safe" },
		"weight": 260,
		"penetration": 95,
		"interactions": [
			{ "id": "open", "label": "Open safe" },
			{ "id": "examine", "label": "Examine" },
		],
	},
}
const ARRANGEMENTS := {
	"crate_corner": {
		"placement": "wall", "footprint": Vector2(46, 46), "prefer_corner": true,
		"tags": ["crates"],
		"items": [{ "key": "crate_stack", "pos": Vector2(23, 23) }],
	},
	"crate_free": {
		"placement": "center", "footprint": Vector2(46, 46), "tags": ["crates_free"],
		"items": [{ "key": "crate_stack", "pos": Vector2(23, 23) }],
	},
	"pallet_wall": {
		"placement": "wall", "footprint": Vector2(64, 56), "tags": ["pallet"],
		"items": [{ "key": "wrapped_pallet", "pos": Vector2(32, 28) }],
	},
	"pallet_free": {
		"placement": "center", "footprint": Vector2(64, 56), "tags": ["pallet_free"],
		"items": [{ "key": "wrapped_pallet", "pos": Vector2(32, 28) }],
	},
	"safe_wall": {
		"placement": "wall", "footprint": Vector2(36, 32), "prefer_corner": true,
		"tags": ["safe"],
		"items": [{ "key": "wall_safe", "pos": Vector2(18, 16) }],
	},
}
const RECIPES := {
	"stockroom": {
		"clutter": [["cardboard", 3.0], ["trash", 2.0], ["puddle", 1.0], ["cables", 0.5]],
		"palettes": [
			{
				"wood": GeneralCatalog.WOOD.charcoal,
				"fabric": GeneralCatalog.FABRIC.slate,
				"floor": "concrete",
			},
		],
		"zones": [
			{
				"options": ["crate_corner", "crate_free"],
				"count": Vector2i(1, 2),
				"required": true,
			},
			{ "options": ["pallet_wall", "pallet_free"], "count": Vector2i(1, 2) },
			{ "options": ["safe_wall"], "count": Vector2i(0, 1) },
		],
	},
}
