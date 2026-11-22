class_name LooseStockCatalog
## World Generation domain: the items the shelves and the stockroom give up (`docs/stacked-items.md`
## SI13, decision D21): a pallet, a shrink-wrapped box, a standing book, a pair of shoes, a paint
## tin, the hotplate's plate (`hob`), a pan and a pot. Each is a small free piece (Objects' `item`
## painter and mesh), like `ItemsCatalog`'s: an emptied piece (`PieceCarries`) sets them where its
## `carries` row names, and `RoomItems` never strews them on a top at random (they are in no `TOPS`
## row).
## The footprints here are a default: a carrying row sets the size, height and colour it needs
## (a book is as tall as its board's room, a loose crate of a stack is 38 px across).

const OBJECTS := {
	"pallet": {
		"name": "Pallet",
		"shape": "rect",
		"size": Vector2(64, 56),
		"color": Color(0.5, 0.38, 0.24),
		"material": "wood",
		"art": "item",
		"art_opts": { "kind": "pallet" },
		"weight": 12,
		"penetration": 20,
	},
	"wrapped_box": {
		"name": "Wrapped box",
		"shape": "rect",
		"size": Vector2(28, 22),
		"color": Color(0.62, 0.48, 0.3),
		"material": "cardboard",
		"art": "item",
		"art_opts": { "kind": "wrapped_box" },
		"weight": 8,
		"penetration": 35,
	},
	"book_stood": {
		"name": "Book",
		"shape": "rect",
		"size": Vector2(3, 12),
		"color": Color(0.45, 0.2, 0.18),
		"material": "paper",
		"art": "item",
		"art_opts": { "kind": "book_stood" },
		"weight": 0.4,
		# A run of up to six books side by side (a hand of paper): a pistol round that goes
		# through it is spent (it loses over half its speed), a rifle round carries on.
		# 70 stands in for the run's thickness; keep it under `penetration_bounce_min` (80) or a
		# round glances off the spines (`projectile/round_through_a_run_of_books` asserts it).
		"penetration": 70,
	},
	"shoes": {
		"name": "Shoes",
		"shape": "rect",
		"size": Vector2(11, 14),
		"color": Color(0.3, 0.24, 0.2),
		"material": "fabric",
		"art": "item",
		"art_opts": { "kind": "shoes" },
		"weight": 0.8,
		"penetration": 8,
	},
	"hob": {
		"name": "Hotplate",
		"shape": "rect",
		"size": Vector2(34, 24),
		"color": Color(0.3, 0.3, 0.32),
		"material": "metal",
		"art": "item",
		"art_opts": { "kind": "hob" },
		"weight": 3,
		"penetration": 40,
	},
	"pan": {
		"name": "Pan",
		"shape": "rect",
		"size": Vector2(19, 14),
		"color": Color(0.2, 0.19, 0.18),
		"material": "metal",
		"art": "item",
		"art_opts": { "kind": "pan" },
		"weight": 1.2,
		"penetration": 20,
	},
	"paint_tin": {
		"name": "Paint tin",
		"shape": "circle",
		"size": Vector2(10, 10),
		"color": Color(0.66, 0.68, 0.72),
		"material": "metal",
		"art": "item",
		"art_opts": { "kind": "paint_tin" },
		"weight": 1.5,
		"penetration": 25,
	},
	"sandbag": {
		"name": "Sandbag",
		"shape": "rect",
		"size": Vector2(15, 8),
		"color": Color(0.55, 0.47, 0.32),
		"material": "fabric",
		"art": "item",
		"art_opts": { "kind": "sandbag" },
		"weight": 14,
		# A bag of sand stops a round as the barricade it flanked did (`penetration` 90).
		"penetration": 90,
	},
	"hat": {
		"name": "Hat",
		"shape": "circle",
		"size": Vector2(10, 10),
		"color": Color(0.42, 0.24, 0.14),
		"material": "fabric",
		"art": "item",
		"art_opts": { "kind": "hat" },
		"weight": 0.3,
		"penetration": 4,
	},
	"pot": {
		"name": "Pot",
		"shape": "circle",
		"size": Vector2(10, 10),
		"color": Color(0.55, 0.56, 0.6),
		"material": "metal",
		"art": "item",
		"art_opts": { "kind": "pot" },
		"weight": 1.5,
		"penetration": 25,
	},
}
