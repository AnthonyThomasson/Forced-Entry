extends RefCounted
## The sets about the tower itself: the lobby floor stencil, the tower's shadow, the podium band
## and awnings and signs. One builder per set, each spawning one exhibit (a slot: its `origin` and
## `variant`) through the stage kit.

const Kit := preload("res://sandboxes/showroom/downtown_district/stage_kit.gd")
const LobbyFloor := preload("res://sandboxes/showroom/downtown_district/lobby_floor_painter.gd")
const Shadow := preload("res://sandboxes/showroom/downtown_district/tower_shadow_painter.gd")
const Podium := preload("res://sandboxes/showroom/downtown_district/podium_painter.gd")
const Awning := preload("res://sandboxes/showroom/downtown_district/awning_painter.gd")
const Fade := preload("res://sandboxes/showroom/downtown_district/character_fade.gd")
const Walker := preload("res://sandboxes/showroom/downtown_district/walker_loop.gd")
const ROOM := Vector2(240, 200)
const FLOORS := ["concrete", "slate_tile"]
const PLOT_W := 300.0
const WALK := 64.0
## Where a lamp stands from the curb and from the plot's right edge.
const LAMP_IN := 10.0
const LAMP_X := 270.0


## Build the exhibit of set `kind` for `slot` through `kit`.
static func build(kit: Kit, kind: StringName, slot: Dictionary) -> void:
	match kind:
		&"lobby":
			_lobby(kit, slot)
		&"shadow":
			_shadow(kit, slot)
		&"podium":
			_podium(kit, slot)
		&"awning":
			_awning(kit, slot)


## Two empty 240 x 200 rooms (a concrete and a tile floor) with the stencil painted on each.
static func _lobby(kit: Kit, slot: Dictionary) -> void:
	var o: Vector2 = slot["origin"]
	for i in FLOORS.size():
		var rect := Rect2(o + Vector2(30, i * 224), ROOM)
		var door_y := rect.position.y if i == 0 else rect.end.y
		kit.room(rect, FLOORS[i], [Vector2(rect.position.x + ROOM.x * 0.5, door_y)])
		kit.sprite(
			LobbyFloor, ROOM, rect.position, { "variant": slot["variant"] },
			{ "z": DrawLayers.RUG },
		)
	kit.piece("chair", o + Vector2(150, 224 + ROOM.y + 40))


## A tower's ground floor (a walled concrete room) beside a real sidewalk and road, its shadow laid
## over them (none for today).
static func _shadow(kit: Kit, slot: Dictionary) -> void:
	var o: Vector2 = slot["origin"]
	var foot := Rect2(o + Vector2(40, 0), Vector2(130, 140))
	kit.room(foot, "concrete", [Vector2(foot.get_center().x, foot.end.y)])
	kit.street(Rect2(o.x, foot.end.y, PLOT_W, WALK), "sidewalk", o, [Vector2.DOWN])
	kit.street(Rect2(o.x, o.y, 40, foot.size.y), "sidewalk", o)
	kit.street(Rect2(foot.end.x, o.y, PLOT_W - 170.0, foot.size.y), "sidewalk", o)
	kit.street(Rect2(o.x, foot.end.y + WALK, PLOT_W, 236), "asphalt", o, [Vector2.UP])
	kit.piece("streetlight", Vector2(o.x + LAMP_X, foot.end.y + WALK - LAMP_IN))
	if slot["variant"] != "today":
		kit.sprite(
			Shadow, Vector2(PLOT_W, 440), o,
			{ "variant": slot["variant"], "foot": Rect2i(40, 0, 130, 140) },
			{ "z": DrawLayers.BLOOD, "street": true },
		)


## The street in front of a wall ending at `wall_end` (world y): a sidewalk of `walk` px, a road
## below it and a real streetlight at the curb.
static func _frontage(
	kit: Kit,
	o: Vector2,
	wall_end: float,
	walk: float,
	road: float,
) -> void:
	kit.street(Rect2(o.x, wall_end, PLOT_W, walk), "sidewalk", o, [Vector2.DOWN])
	kit.street(Rect2(o.x, wall_end + walk, PLOT_W, road), "asphalt", o, [Vector2.UP])
	kit.piece("streetlight", Vector2(o.x + LAMP_X, wall_end + walk - LAMP_IN))


## A tower's ground-floor room with a doorway in its south wall, and the frontage in front of it.
static func _storefront(kit: Kit, rect: Rect2, walk: float, road: float) -> void:
	var o := Vector2(rect.position.x - 0.0, rect.position.y)
	kit.room(rect, "concrete", [Vector2(rect.get_center().x, rect.end.y)])
	_frontage(kit, Vector2(floorf(rect.position.x / 10.0) * 10.0, o.y), rect.end.y, walk, road)


## The podium band along the outside of the south wall (today: the plain house wall).
static func _podium(kit: Kit, slot: Dictionary) -> void:
	var o: Vector2 = slot["origin"]
	var room := Rect2(o, Vector2(PLOT_W, 130))
	kit.room(room, "concrete", [Vector2(room.get_center().x, room.end.y)])
	_frontage(kit, o, room.end.y, 120.0, 150.0)
	if slot["variant"] == "today":
		return
	for x in [0.0, 180.0]:
		kit.sprite(
			Podium, Vector2(120, 40), Vector2(o.x + x, room.end.y + 6),
			{ "variant": slot["variant"] }, { "solid": true, "shadow": true },
		)


## The storefront's door with what hangs over the sidewalk in front of it.
static func _awning(kit: Kit, slot: Dictionary) -> void:
	var o: Vector2 = slot["origin"]
	var room := Rect2(o, Vector2(PLOT_W, 120))
	var door := Vector2(room.get_center().x, room.end.y)
	kit.room(room, "concrete", [door])
	kit.door("glass", "panes", door, door - Vector2(24, 0), Vector2.UP)
	_frontage(kit, o, room.end.y, 90.0, 120.0)
	var over := { "z": DrawLayers.OVERHEAD, "street": true }
	match slot["variant"]:
		"a":
			kit.sprite(
				Awning,
				Vector2(110, 46),
				door - Vector2(55, -6),
				{ "kind": "awning" },
				over.merged({ "shadow": true, "shift": 9 }),
			)
		"b":
			kit.sprite(
				Awning,
				Vector2(30, 74),
				door + Vector2(46, 4),
				{ "kind": "sign_box" },
				over.merged({ "shadow": true, "shift": 12 }),
			)
		"c":
			_fading_awning(kit, door, slot, over)


## Variant C: a dark awning and a hanging glyph sign over the door, each fading to a ghost while any
## character (the player, or the slot's `walker` looping under both) is beneath it.
static func _fading_awning(kit: Kit, door: Vector2, slot: Dictionary, over: Dictionary) -> void:
	var awning := Vector2(110, 46)
	var sign_size := Vector2(28, 76)
	var hung: Array = [
		[awning, door - Vector2(55, -6), { "kind": "awning", "palette": "c" }, 9],
		[sign_size, door + Vector2(64, 4), { "kind": "hanging" }, 12],
	]
	for part: Array in hung:
		var drawing: Node2D = kit.sprite(
			Awning, part[0], part[1], part[2], over.merged({ "shadow": true, "shift": part[3] }),
		)
		var fade := Fade.new()
		fade.drawing = drawing
		fade.size = part[0]
		kit.add(fade)
	var loop := Walker.new()
	loop.walker = slot["walker"]
	loop.park = slot["park"]
	loop.points = [door + Vector2(-95, 35), door + Vector2(125, 35)]
	kit.add(loop)
