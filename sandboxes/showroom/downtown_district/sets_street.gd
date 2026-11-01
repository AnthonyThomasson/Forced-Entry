extends RefCounted
## The sets about the street: the crosswalk and junction, the road glyphs and the sidewalk clutter,
## each on the real asphalt and sidewalk floors beside a real streetlight. One builder per set,
## each spawning one exhibit (a slot: its `origin` and `variant`) through the stage kit.

const Kit := preload("res://sandboxes/showroom/downtown_district/stage_kit.gd")
const Crosswalk := preload("res://sandboxes/showroom/downtown_district/crosswalk_painter.gd")
const RoadGlyphs := preload("res://sandboxes/showroom/downtown_district/road_glyph_painter.gd")
const Props := preload("res://sandboxes/showroom/downtown_district/street_prop_painter.gd")
const PLOT_W := 300.0
## The crossing: the vertical road's x and width, the horizontal road's y and height, the plot's
## height.
const V_X := 90.0
const V_W := 120.0
const H_Y := 160.0
const H_H := 120.0
const PLOT_H := 440.0
## The glyph road: its x and width, the lane middles inside it, and its height.
const ROAD_X := 40.0
const ROAD_W := 220.0
const ROAD_H := 400.0
const LANES := [55, 165]


## Build the exhibit of set `kind` for `slot` through `kit`.
static func build(kit: Kit, kind: StringName, slot: Dictionary) -> void:
	match kind:
		&"crossing":
			_crossing(kit, slot)
		&"glyphs":
			_glyphs(kit, slot)
		&"clutter":
			_clutter(kit, slot)


## A four-way junction on real asphalt (the lane dashes down the vertical road) with a sidewalk
## block in each corner; the crossings' paint over it (none for today).
static func _crossing(kit: Kit, slot: Dictionary) -> void:
	var o: Vector2 = slot["origin"]
	var south_y := H_Y + H_H
	var corners := [
		[Rect2(0, 0, V_X, H_Y), [Vector2.RIGHT, Vector2.DOWN]],
		[Rect2(V_X + V_W, 0, V_X, H_Y), [Vector2.LEFT, Vector2.DOWN]],
		[Rect2(0, south_y, V_X, PLOT_H - south_y), [Vector2.RIGHT, Vector2.UP]],
		[Rect2(V_X + V_W, south_y, V_X, PLOT_H - south_y), [Vector2.LEFT, Vector2.UP]],
	]
	for corner: Array in corners:
		var r: Rect2 = corner[0]
		kit.street(Rect2(o + r.position, r.size), "sidewalk", o, corner[1])
	var sides := [Vector2.LEFT, Vector2.RIGHT]
	kit.street(Rect2(o.x + V_X, o.y, V_W, H_Y), "asphalt", o, sides, true)
	kit.street(Rect2(o.x + V_X, o.y + south_y, V_W, PLOT_H - south_y), "asphalt", o, sides, true)
	kit.street(Rect2(o.x + V_X, o.y + H_Y, V_W, H_H), "asphalt", o)
	kit.street(Rect2(o.x, o.y + H_Y, V_X, H_H), "asphalt", o, [Vector2.UP, Vector2.DOWN])
	kit.street(
		Rect2(o.x + V_X + V_W, o.y + H_Y, V_X, H_H),
		"asphalt",
		o,
		[Vector2.UP, Vector2.DOWN],
	)
	kit.piece("streetlight", o + Vector2(V_X - 12, H_Y - 40), { "facing": Vector2.RIGHT })
	kit.piece("streetlight", o + Vector2(V_X + V_W + 12, south_y + 40), { "facing": Vector2.LEFT })
	if slot["variant"] == "today":
		return
	kit.sprite(
		Crosswalk, Vector2(PLOT_W, PLOT_H), o,
		{
			"variant": slot["variant"], "v": Rect2i(int(V_X), 0, int(V_W), int(PLOT_H)),
			"h": Rect2i(0, int(H_Y), int(PLOT_W), int(H_H)),
		},
		{ "z": DrawLayers.BLOOD, "street": true },
	)


## A two-lane road on real asphalt between two sidewalks, the painted glyphs over it.
static func _glyphs(kit: Kit, slot: Dictionary) -> void:
	var o: Vector2 = slot["origin"]
	kit.street(Rect2(o.x, o.y, ROAD_X, ROAD_H), "sidewalk", o, [Vector2.RIGHT])
	kit.street(Rect2(o.x + ROAD_X + ROAD_W, o.y, ROAD_X, ROAD_H), "sidewalk", o, [Vector2.LEFT])
	kit.street(
		Rect2(o.x + ROAD_X, o.y, ROAD_W, ROAD_H), "asphalt", o, [Vector2.LEFT, Vector2.RIGHT], true,
	)
	kit.piece("streetlight", o + Vector2(ROAD_X - 12, ROAD_H - 60), { "facing": Vector2.RIGHT })
	kit.sprite(
		RoadGlyphs, Vector2(ROAD_W, ROAD_H), o + Vector2(ROAD_X, 0),
		{ "variant": slot["variant"], "lanes": LANES },
		{ "z": DrawLayers.BLOOD, "street": true },
	)


## A sidewalk under a real house wall and a real streetlight, laid with a vending machine, a bench,
## a bin, a drain grate and litter in one style family.
static func _clutter(kit: Kit, slot: Dictionary) -> void:
	var o: Vector2 = slot["origin"]
	var look: String = slot["variant"]
	var wall := Rect2(o, Vector2(PLOT_W, 110))
	kit.room(wall, "concrete", [Vector2(wall.get_center().x, wall.end.y)])
	var curb := wall.end.y + 130.0
	kit.street(Rect2(o.x, wall.end.y, PLOT_W, 130), "sidewalk", o, [Vector2.DOWN])
	kit.street(Rect2(o.x, curb, PLOT_W, 110), "asphalt", o, [Vector2.UP])
	kit.piece("streetlight", Vector2(o.x + 270, curb - 10))
	kit.piece_at("chair", o + Vector2(250, wall.end.y + 20))
	var solid := { "solid": true, "shadow": true }
	kit.sprite(
		Props,
		Vector2(40, 34),
		o + Vector2(14, wall.end.y + 8),
		{ "kind": "vending", "look": look },
		solid,
	)
	kit.sprite(
		Props,
		Vector2(74, 26),
		o + Vector2(76, wall.end.y + 14),
		{ "kind": "bench", "look": look },
		solid,
	)
	kit.sprite(
		Props,
		Vector2(26, 26),
		o + Vector2(176, wall.end.y + 14),
		{ "kind": "bin", "look": look },
		solid,
	)
	kit.sprite(
		Props,
		Vector2(40, 18),
		o + Vector2(120, curb - 22),
		{ "kind": "grate", "look": look },
		{ "z": DrawLayers.BLOOD, "street": true },
	)
	kit.sprite(
		Props,
		Vector2(44, 30),
		o + Vector2(190, wall.end.y + 70),
		{ "kind": "litter", "look": look },
		{ "z": DrawLayers.LYING, "street": true },
	)
