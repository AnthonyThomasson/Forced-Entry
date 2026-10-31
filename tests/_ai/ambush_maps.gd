extends RefCounted
## The layout of the ambush tests (`docs/leadership.md` LD15, D17, D18; not a test itself):
## `const AmbushMap := preload("res://tests/_ai/ambush_maps.gd")`. One room laid with
## `TestSetup.layout`, as `flank_maps.gd` lays its maps: `room(s)` fills a TestSetup, and its
## landmarks are consts, so a test names a place instead of a raw coordinate.
##
## A room 600 x 400 (the "living room") over a hall along its south side, a doorway between them
## (80 px, centred at (100, 400)) and the front door at the hall's west end. A wardrobe (95 tall,
## above a crouched body) stands in the room north of the door's wall, east of the doorway: between
## some of the hidden posts tucked against the door's wall and where a grenade thrown in by the
## doorway comes down.
##
##   x 0 ............................ 600
##   +--------------------------------+   y 0
##   |  LIVING ROOM                   |
##   |                [W]             |   the wardrobe at (360, 300)
##   +---[ ]--------------------------+   y 400, the doorway at x 100
##   [ HALL                           |   y 400-510, the front door on the west end
##   +--------------------------------+

const ROOM := Rect2(0, 0, 600, 400)
const HALL := Rect2(0, 400, 600, 110)
## The doorway between the room and the hall, on the wall's centreline, and its id.
const DOOR := Vector2(100, 400)
const DOOR_ID := "door_100_400"
const DOOR_WIDTH := 80.0
## The unit normal out of the room through the doorway: into the hall.
const OUT := Vector2.DOWN
## The front door, in the hall's west wall.
const FRONT_DOOR := Vector2(0, 455)
const WARDROBE_AT := Vector2(360, 300)


## Lay the room, the hall, their doorway, the front door and the wardrobe.
static func room(s: TestSetup) -> void:
	s.layout(
		[
			{ "key": "living_room", "type": "living_room", "rect": ROOM, "floor": "oak_planks" },
			{ "key": "hall", "type": "hallway", "rect": HALL, "floor": "oak_planks" },
		],
		[{ "pos": DOOR, "width": DOOR_WIDTH }, { "pos": FRONT_DOOR, "width": 80.0 }],
	)
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT)
