class_name StockroomCatalog
## World Generation domain: stockroom objects, arrangements and recipe: the back room of a shop or
## noodle bar. Stacked crates, a pallet of wrapped boxes and a wall safe (Objects' `stock`
## painter). Shared clutter (cardboard, trash) lives in GeneralCatalog.

const OBJECTS := {
	"crate_stack": {
		"name": "Crates",
		"shape": "rect",
		"size": Vector2(46, 46),
		"color": Color(0.5, 0.38, 0.24),
		"material": "wood",
		"art": "stock",
		"art_opts": { "kind": "crates" },
		"weight": 80,
		"coverage": 90,
		"penetration": 40,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
	"wrapped_pallet": {
		"name": "Pallet",
		"shape": "rect",
		"size": Vector2(64, 56),
		"color": Color(0.5, 0.38, 0.24),
		"material": "wood",
		"art": "stock",
		"art_opts": { "kind": "pallet" },
		"weight": 90,
		"coverage": 75,
		"penetration": 35,
		"interactions": [{ "id": "examine", "label": "Examine" }],
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
		"coverage": 100,
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
