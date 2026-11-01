class_name ShopCatalog
## World Generation domain: shop objects, arrangements and recipe: the tower's convenience store
## (LayoutRules lets it carry the front door). A steel counter with a till, double-sided shelf
## aisles, a glass drinks fridge and a snack machine, all grimy steel (Objects' `shop` painter).
## Shared clutter (trash, cardboard, puddles) lives in GeneralCatalog.

const STEEL := Color(0.46, 0.47, 0.45)
const OBJECTS := {
	"shop_counter": {
		"name": "Shop counter",
		"shape": "rect",
		"size": Vector2(110, 44),
		"color": STEEL,
		"material": "metal",
		"art": "shop",
		"art_opts": { "kind": "counter" },
		"weight": 120,
		"coverage": 70,
		"penetration": 60,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
	"shelf_aisle": {
		"name": "Shelf aisle",
		"shape": "rect",
		"size": Vector2(120, 40),
		"color": STEEL,
		"material": "metal",
		"art": "shop",
		"art_opts": { "kind": "aisle" },
		"weight": 100,
		"coverage": 85,
		"penetration": 55,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
	"drinks_fridge": {
		"name": "Drinks fridge",
		"shape": "rect",
		"size": Vector2(64, 36),
		"color": STEEL,
		"material": "metal",
		"art": "shop",
		"art_opts": { "kind": "fridge" },
		"weight": 140,
		"coverage": 100,
		"penetration": 70,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
	"snack_machine": {
		"name": "Snack machine",
		"shape": "rect",
		"size": Vector2(46, 34),
		"color": STEEL,
		"material": "metal",
		"art": "shop",
		"art_opts": { "kind": "snack" },
		"weight": 130,
		"coverage": 100,
		"penetration": 70,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
}
const ARRANGEMENTS := {
	"shop_counter_wall": {
		"placement": "wall", "footprint": Vector2(110, 44), "prefer_corner": true,
		"tags": ["shop_counter"],
		"items": [{ "key": "shop_counter", "pos": Vector2(55, 22) }],
	},
	"shelf_aisle_run": {
		"placement": "center", "footprint": Vector2(120, 40), "tags": ["aisle_run"],
		"items": [{ "key": "shelf_aisle", "pos": Vector2(60, 20) }],
	},
	"shelf_aisle_wall": {
		"placement": "wall", "footprint": Vector2(120, 40), "tags": ["aisle_wall"],
		"items": [{ "key": "shelf_aisle", "pos": Vector2(60, 20) }],
	},
	"fridge_wall": {
		"placement": "wall", "footprint": Vector2(64, 36), "prefer_corner": true,
		"tags": ["fridge"],
		"items": [{ "key": "drinks_fridge", "pos": Vector2(32, 18) }],
	},
	"snack_wall": {
		"placement": "wall", "footprint": Vector2(46, 34), "prefer_corner": true,
		"tags": ["snack"],
		"items": [{ "key": "snack_machine", "pos": Vector2(23, 17) }],
	},
}
const RECIPES := {
	"shop": {
		"clutter": [["trash", 3.0], ["cardboard", 2.0], ["puddle", 1.5], ["cables", 0.5]],
		"palettes": [
			{
				"wood": GeneralCatalog.WOOD.charcoal,
				"fabric": GeneralCatalog.FABRIC.slate,
				"floor": "concrete",
			},
			{
				"wood": GeneralCatalog.WOOD.walnut,
				"fabric": GeneralCatalog.FABRIC.terracotta,
				"floor": "slate_tile",
			},
		],
		"zones": [
			{
				"options": ["shop_counter_wall"],
				"count": Vector2i(1, 1),
				"required": true,
			},
			{ "options": ["shelf_aisle_run", "shelf_aisle_wall"], "count": Vector2i(1, 2) },
			{ "options": ["fridge_wall"], "count": Vector2i(1, 1) },
			{ "options": ["snack_wall"], "count": Vector2i(1, 1) },
		],
	},
}
