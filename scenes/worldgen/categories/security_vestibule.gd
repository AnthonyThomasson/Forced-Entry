class_name SecurityVestibuleCatalog
## World Generation domain: security-vestibule objects, arrangements and recipe: the room behind the
## front door (LayoutRules lets it carry it) where callers are checked. A row of steel lockers, the
## two posts of a scanner arch and a barricade slab with sandbags. Shared pieces (a coat and shoe
## area, a bench, a runner) live in GeneralCatalog.

const OBJECTS := {
	"barricade": {
		"name": "Barricade",
		"shape": "rect",
		"size": Vector2(120, 28),
		"color": Color(0.5, 0.5, 0.48),
		"material": "metal",
		"art": "security",
		"art_opts": { "kind": "barricade" },
		# The sandbags at both ends (SI15): two stacks of three side by side (15 by 8 px, 10 high),
		# a smaller bag on each middle one; `at` from the piece's centre where the painter drew
		# them.
		"carries": [
			{ "key": "sandbag", "at": Vector2(-52.5, -9), "lift": 0.0 },
			{ "key": "sandbag", "at": Vector2(-49.5, -1), "lift": 0.0 },
			{ "key": "sandbag", "at": Vector2(-52.5, 7), "lift": 0.0 },
			{ "key": "sandbag", "at": Vector2(51.5, -9), "lift": 0.0 },
			{ "key": "sandbag", "at": Vector2(54.5, -1), "lift": 0.0 },
			{ "key": "sandbag", "at": Vector2(51.5, 7), "lift": 0.0 },
			{
				"key": "sandbag", "at": Vector2(-49.5, -1), "lift": 10.0,
				"size": Vector2(11, 4), "height": 6.0,
			},
			{
				"key": "sandbag", "at": Vector2(54.5, -1), "lift": 10.0,
				"size": Vector2(11, 4), "height": 6.0,
			},
		],
		"weight": 160,
		"penetration": 90,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
	"scanner_post": {
		"name": "Scanner",
		"shape": "square",
		"size": Vector2(22, 22),
		"color": Color(0.4, 0.4, 0.44),
		"material": "metal",
		"art": "security",
		"art_opts": { "kind": "scanner" },
		"weight": 200,
		"penetration": 80,
		"interactions": [{ "id": "examine", "label": "Examine" }],
	},
	"lockers": {
		"name": "Lockers",
		"shape": "rect",
		"size": Vector2(100, 36),
		"color": Color(0.5, 0.52, 0.56),
		"material": "metal",
		"art": "security",
		"art_opts": { "kind": "lockers" },
		"weight": 90,
		"penetration": 70,
		"interactions": [
			{ "id": "open", "label": "Open locker" },
			{ "id": "examine", "label": "Examine" },
		],
	},
}
const ARRANGEMENTS := {
	"locker_wall": {
		"placement": "wall", "footprint": Vector2(
			100,
			36,
		), "prefer_corner": true, "tags": ["lockers"],
		"items": [{ "key": "lockers", "pos": Vector2(50, 18) }],
	},
	# The two posts of the arch, their emitters facing each other across a gap a body walks through.
	"scanner_arch": {
		"placement": "center", "footprint": Vector2(112, 22), "tags": ["scanner"],
		"items": [
			{ "key": "scanner_post", "pos": Vector2(11, 11), "facing": Vector2.RIGHT },
			{ "key": "scanner_post", "pos": Vector2(101, 11), "facing": Vector2.LEFT },
		],
	},
	"barricade_line": {
		"placement": "center", "footprint": Vector2(120, 28), "tags": ["barricade"],
		"items": [{ "key": "barricade", "pos": Vector2(60, 14) }],
	},
}
const RECIPES := {
	"security_vestibule": {
		"clutter": [["trash", 2.0], ["cardboard", 2.0], ["puddle", 1.5]],
		"palettes": [
			{
				"wood": GeneralCatalog.WOOD.charcoal,
				"fabric": GeneralCatalog.FABRIC.slate,
				"floor": "slate_tile",
			},
			{
				"wood": GeneralCatalog.WOOD.walnut,
				"fabric": GeneralCatalog.FABRIC.terracotta,
				"floor": "concrete",
			},
		],
		"zones": [
			{
				"options": ["locker_wall"],
				"count": Vector2i(1, 1),
				"required": true,
				"fallback": "barricade_line",
			},
			{ "options": ["scanner_arch", "barricade_line"], "count": Vector2i(1, 2) },
			{ "options": ["bench_coats", "entry_area"], "count": Vector2i(0, 1) },
		],
		"fill": {
			"target": 0.2,
			"options": ["locker_wall", "entry_area", "lamp_corner", "plant_corner", "runner_hall"],
		},
	},
}
