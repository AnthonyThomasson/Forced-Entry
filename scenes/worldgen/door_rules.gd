class_name DoorRules
## World Generation domain: which doorways of a house get a door, which way it swings and how it
## starts, as tunable data plus a few pure lookups (`docs/doors.md` DR2 to DR4). A `class_name`
## holder of constants and statics, in the style of `LayoutRules`: read as `DoorRules.<name>`, no
## instance, no autoload.
##
##   ROOMS  per room TYPE: `rank` (how private the room is, the higher the more private: an
##          interior door swings into the more private of its two rooms) and `chance` (the share of
##          the doorways it is the more private room of that get a door). A type with no entry
##          gets DEFAULT_ROOM.
##   SETS   the door sets: which `DoorCatalog` doors (by key) a kind of doorway draws from, `front`
##          for the front doorway, `exit` for an exit and `interior`. A floorplan names its own sets
##          (`door_sets`, and an opening's `door_set` picks one of them); a kind it does not name
##          draws from SETS.
## The front and exit doorways always get a door (`chance`'s caller), and a floorplan can force or
## forbid a door on one opening (`door: true` / `false`).

## A room type that has no ROOMS entry.
const DEFAULT_ROOM := { "rank": 1, "chance": 0.15 }
## Bathrooms and the netrunner den always get their door; bedrooms, offices and ripperdocs mostly;
## the garage, the laundry and a stockroom about half the time; kitchens, living spaces, the studio,
## the vestibule, a shop, a noodle bar and the elevator lobby rarely; and a hallway never (so no
## door between two hallways).
const ROOMS := {
	"bathroom": { "rank": 4, "chance": 1.0 },
	"netrunner_den": { "rank": 4, "chance": 1.0 },
	"bedroom": { "rank": 3, "chance": 0.85 },
	"home_office": { "rank": 3, "chance": 0.85 },
	"ripperdoc": { "rank": 3, "chance": 0.85 },
	"garage": { "rank": 2, "chance": 0.5 },
	"laundry_room": { "rank": 2, "chance": 0.5 },
	"kitchen": { "rank": 1, "chance": 0.15 },
	"kitchenette": { "rank": 1, "chance": 0.15 },
	"living_room": { "rank": 1, "chance": 0.15 },
	"kitchen_living": { "rank": 1, "chance": 0.15 },
	"studio": { "rank": 1, "chance": 0.15 },
	"security_vestibule": { "rank": 1, "chance": 0.15 },
	"hallway": { "rank": 0, "chance": 0.0 },
	"shop": { "rank": 1, "chance": 0.15 },
	"noodle_bar": { "rank": 1, "chance": 0.15 },
	"stockroom": { "rank": 2, "chance": 0.5 },
	"elevator_lobby": { "rank": 1, "chance": 0.15 },
}
## The default door sets, by kind of doorway: the houses' solid wood at the street and at an exit,
## hollow-core inside.
const SETS := {
	"front": ["solid_panelled", "solid_plank"],
	"exit": ["solid_panelled", "solid_plank"],
	"interior": ["hollow_flush", "hollow_panelled"],
}
## The chance that a tie goes to the first of the two (the room an interior door swings into when
## both are as private, the jamb it is hinged on when both are as near the corner).
const TIE_FIRST := 0.5
## How a door starts, by weight (an interior door; the front and exit ones start shut).
const START_WEIGHTS := { "shut": 0.6, "ajar": 0.15, "open": 0.25 }
## The angle (degrees from shut) an ajar door starts at, from the least to the most.
const AJAR_DEGREES := Vector2(15.0, 35.0)


## The row of `room_type`: DEFAULT_ROOM, or its ROOMS entry.
static func room(room_type: String) -> Dictionary:
	return ROOMS.get(room_type, DEFAULT_ROOM)


## How private a room of `room_type` is (the higher, the more private).
static func rank(room_type: String) -> int:
	return room(room_type)["rank"]


## The chance that a doorway between rooms of `type_a` and `type_b` has a door: that of the more
## private of the two (the larger, when both are as private).
static func chance(type_a: String, type_b: String) -> float:
	var top := maxi(rank(type_a), rank(type_b))
	var best := 0.0
	for type in [type_a, type_b]:
		if rank(type) == top:
			best = maxf(best, room(type)["chance"])
	return best


## The door keys a doorway of `kind` (`front`, `exit`, `interior`, or a set a floorplan names)
## draws from: the floorplan's `door_sets` entry, else SETS'.
static func set_of(kind: String, plan_sets: Dictionary) -> Array:
	return plan_sets.get(kind, SETS.get(kind, SETS["interior"]))
