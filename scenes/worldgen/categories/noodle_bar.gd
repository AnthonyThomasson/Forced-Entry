class_name NoodleBarCatalog
## World Generation domain: noodle-bar objects, arrangements and recipe: the tower's cook-shop
## (LayoutRules lets it carry the front door). A long bar counter with its stools in front, booths
## and a menu board, in grimy steel (Objects' `noodle` painter). The cooking line (the kitchen's
## `cooking_line`) is reused behind the bar. Shared clutter lives in GeneralCatalog.

const STEEL := Color(0.46, 0.47, 0.45)
const OBJECTS := {
	"noodle_counter": {
		"name": "Noodle bar",
		"shape": "rect",
		"size": Vector2(150, 34),
		"color": STEEL,
		"material": "metal",
		"art": "noodle",
		"art_opts": { "kind": "bar" },
		"weight": 130,
		"coverage": 70,
		"penetration": 60,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
	"bar_stool": {
		"name": "Bar stool",
		"shape": "circle",
		"size": Vector2(20, 20),
		"color": STEEL,
		"material": "metal",
		"art": "noodle",
		"art_opts": { "kind": "stool" },
		"weight": 7,
		"coverage": 20,
		"penetration": 30,
		"interactions": [{ "id": "sit", "label": "Sit", "move_to": true }],
	},
	"noodle_booth": {
		"name": "Booth",
		"shape": "rect",
		"size": Vector2(96, 64),
		"color": STEEL,
		"material": "metal",
		"art": "noodle",
		"art_opts": { "kind": "booth" },
		"weight": 110,
		"coverage": 60,
		"penetration": 50,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
	"menu_board": {
		"name": "Menu board",
		"shape": "rect",
		"size": Vector2(100, 20),
		"color": STEEL,
		"material": "metal",
		"art": "noodle",
		"art_opts": { "kind": "menu" },
		"weight": 30,
		"coverage": 40,
		"penetration": 40,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
}
const ARRANGEMENTS := {
	# The bar against the wall, three stools on the diners' side of it.
	"noodle_bar_line": {
		"placement": "wall", "footprint": Vector2(150, 62), "prefer_corner": true,
		"tags": ["noodle_bar"],
		"items": [
			{ "key": "noodle_counter", "pos": Vector2(75, 17) },
			{ "key": "bar_stool", "pos": Vector2(30, 50) },
			{ "key": "bar_stool", "pos": Vector2(75, 50) },
			{ "key": "bar_stool", "pos": Vector2(120, 50) },
		],
	},
	"noodle_bar_compact": {
		"placement": "wall", "footprint": Vector2(150, 34), "prefer_corner": true,
		"tags": ["noodle_bar"],
		"items": [{ "key": "noodle_counter", "pos": Vector2(75, 17) }],
	},
	"booth_wall": {
		"placement": "wall", "footprint": Vector2(96, 64), "prefer_corner": true,
		"tags": ["booth"],
		"items": [{ "key": "noodle_booth", "pos": Vector2(48, 32) }],
	},
	"booth_free": {
		"placement": "center", "footprint": Vector2(96, 64), "tags": ["booth_free"],
		"items": [{ "key": "noodle_booth", "pos": Vector2(48, 32) }],
	},
	"menu_wall": {
		"placement": "wall", "footprint": Vector2(100, 20), "tags": ["menu"],
		"items": [{ "key": "menu_board", "pos": Vector2(50, 10) }],
	},
}
const RECIPES := {
	"noodle_bar": {
		"clutter": [["trash", 3.0], ["puddle", 2.0], ["cardboard", 1.0]],
		"palettes": [
			{
				"wood": GeneralCatalog.WOOD.charcoal,
				"fabric": GeneralCatalog.FABRIC.slate,
				"floor": "concrete",
			},
			{
				"wood": GeneralCatalog.WOOD.walnut,
				"fabric": GeneralCatalog.FABRIC.terracotta,
				"floor": "terracotta_tile",
			},
		],
		"zones": [
			{
				"options": ["noodle_bar_line"],
				"count": Vector2i(1, 1),
				"required": true,
				"fallback": "noodle_bar_compact",
			},
			{ "options": ["menu_wall"], "count": Vector2i(1, 1) },
			{ "options": ["booth_wall", "booth_free"], "count": Vector2i(1, 2) },
			{ "options": ["cooking_line", "cooking_compact"], "count": Vector2i(1, 1) },
		],
	},
}
