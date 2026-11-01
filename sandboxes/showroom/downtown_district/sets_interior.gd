extends RefCounted
## The sets of the new room types' pieces: the bodega's shop pieces, the noodle bar's and the
## stockroom's. Each exhibit is a walled room (a real floor, the house wall style) with today's
## closest catalogue pieces (real, through `piece`) or one style family's variants (showroom
## sprites, `look` `a` / `b` / `c`). One builder per set, spawning one exhibit through the stage
## kit.

const Kit := preload("res://sandboxes/showroom/downtown_district/stage_kit.gd")
const Shop := preload("res://sandboxes/showroom/downtown_district/shop_painter.gd")
const Noodle := preload("res://sandboxes/showroom/downtown_district/noodle_painter.gd")
const Stock := preload("res://sandboxes/showroom/downtown_district/stock_painter.gd")
const ROOM := Vector2(300, 270)
const SOLID := { "solid": true, "shadow": true }


## Build the exhibit of set `kind` for `slot` through `kit`.
static func build(kit: Kit, kind: StringName, slot: Dictionary) -> void:
	var o: Vector2 = slot["origin"]
	var rect := Rect2(o, ROOM)
	kit.room(rect, _floor(kind), [Vector2(rect.get_center().x, rect.end.y)])
	var today: bool = slot["variant"] == "today"
	match kind:
		&"shop":
			if today:
				_shop_today(kit, o)
			else:
				_shop(kit, o, slot["variant"])
		&"noodle":
			if today:
				_noodle_today(kit, o)
			else:
				_noodle(kit, o, slot["variant"])
		&"stock":
			if today:
				_stock_today(kit, o)
			else:
				_stock(kit, o, slot["variant"])


static func _floor(kind: StringName) -> String:
	match kind:
		&"noodle":
			return "terracotta_tile"
		&"stock":
			return "concrete"
		_:
			return "slate_tile"


static func _shop(kit: Kit, o: Vector2, look: String) -> void:
	kit.sprite(
		Shop,
		Vector2(100, 44),
		o + Vector2(18, 16),
		{ "kind": "counter", "look": look },
		SOLID,
	)
	kit.piece_at("chair", o + Vector2(130, 24))
	kit.sprite(
		Shop,
		Vector2(100, 62),
		o + Vector2(30, 120),
		{ "kind": "aisle", "look": look },
		SOLID,
	)
	kit.sprite(
		Shop,
		Vector2(58, 36),
		o + Vector2(228, 14),
		{ "kind": "fridge", "look": look },
		SOLID,
	)
	kit.sprite(
		Shop,
		Vector2(42, 34),
		o + Vector2(240, 100),
		{ "kind": "snack", "look": look },
		SOLID,
	)


static func _shop_today(kit: Kit, o: Vector2) -> void:
	kit.piece_at("kitchen_counter", o + Vector2(18, 14))
	kit.piece_at("chair", o + Vector2(130, 24))
	kit.piece_at("shelving", o + Vector2(30, 120))
	kit.piece_at("shelving", o + Vector2(30, 160))
	kit.piece_at("fridge", o + Vector2(226, 12))


static func _noodle(kit: Kit, o: Vector2, look: String) -> void:
	kit.sprite(
		Noodle,
		Vector2(150, 34),
		o + Vector2(14, 14),
		{ "kind": "bar", "look": look },
		SOLID,
	)
	for k in 5:
		kit.sprite(
			Noodle,
			Vector2(20, 20),
			o + Vector2(24 + k * 28, 58),
			{ "kind": "stool", "look": look },
			SOLID,
		)
	kit.sprite(
		Noodle,
		Vector2(110, 66),
		o + Vector2(18, 150),
		{ "kind": "booth", "look": look },
		SOLID,
	)
	kit.sprite(
		Noodle,
		Vector2(96, 18),
		o + Vector2(186, 10),
		{ "kind": "menu", "look": look },
		{ "shadow": true },
	)


static func _noodle_today(kit: Kit, o: Vector2) -> void:
	kit.piece_at("kitchen_counter", o + Vector2(14, 14))
	kit.piece_at("stove", o + Vector2(114, 14))
	for k in 3:
		kit.piece_at("chair", o + Vector2(24 + k * 34, 70))
	kit.piece_at("table", o + Vector2(24, 150))


static func _stock(kit: Kit, o: Vector2, look: String) -> void:
	kit.sprite(
		Stock,
		Vector2(46, 46),
		o + Vector2(14, 14),
		{ "kind": "crates", "look": look },
		SOLID,
	)
	kit.sprite(
		Stock,
		Vector2(46, 46),
		o + Vector2(66, 22),
		{ "kind": "crates", "look": look },
		SOLID,
	)
	kit.sprite(
		Stock,
		Vector2(64, 52),
		o + Vector2(190, 120),
		{ "kind": "pallet", "look": look },
		SOLID,
	)
	kit.sprite(Stock, Vector2(34, 22), o + Vector2(220, 8), { "kind": "safe", "look": look }, SOLID)


static func _stock_today(kit: Kit, o: Vector2) -> void:
	kit.piece_at("shelving", o + Vector2(14, 14))
	kit.piece_at("shelving", o + Vector2(120, 14))
	kit.piece_at("cardboard", o + Vector2(190, 120))
	kit.piece_at("cardboard", o + Vector2(230, 150))
