class_name TowerDefinitions
## World Generation domain: the tower ground-floor plans of a downtown district, in
## `HouseDefinitions`' plan format (rooms, openings, door_sets; plan-local coordinates, the front
## door on the south wall). Each plan has exactly one front door, at most one `exit` (a steel back
## door) and exactly one `elevator_lobby` (about 240 x 200 px, one interior doorway, no exterior
## door): a placeholder room for the stairs and elevators to come. A shop or noodle bar at the front
## has a glass shopfront; the others and the back exits are steel. `HouseSpawner.spawn` finds a plan
## here as in `HouseDefinitions`, whose `get_all()` stays the list of houses (a random pick never
## lands on a tower). LayoutRules and tests/worldgen/tower_plans_connected_test.gd hold each plan to
## the same rules as a house.

const SHOPFRONT := {
	"front": ["glass_panes"],
	"exit": ["steel_riveted", "steel_peephole"],
}
const STEEL_FRONT := {
	"front": ["steel_riveted", "steel_peephole"],
	"exit": ["steel_riveted", "steel_peephole"],
}
const PLANS := {
	# A bodega: the shop on the street, the lobby and a stockroom (with the back exit) behind it.
	"bodega_tower": {
		"wall_thickness": 12.0,
		"door_sets": SHOPFRONT,
		"rooms": [
			{ "key": "elevator_lobby", "type": "elevator_lobby", "rect": Rect2(0, 0, 240, 200) },
			{ "key": "stockroom", "type": "stockroom", "rect": Rect2(240, 0, 280, 200) },
			{ "key": "shop", "type": "shop", "rect": Rect2(0, 200, 520, 280) },
		],
		"openings": [
			{ "pos": Vector2(260, 480), "width": 69.0, "front": true },  # shop, shopfront
			{ "pos": Vector2(520, 100), "width": 69.0, "exit": true },  # stockroom, back door
			{ "pos": Vector2(120, 200), "width": 60.0 },  # shop <-> lobby
			{ "pos": Vector2(400, 200), "width": 60.0 },  # shop <-> stockroom
		],
	},
	# A noodle bar on the street, the lobby and a stockroom (with a side exit) behind it.
	"noodle_tower": {
		"wall_thickness": 12.0,
		"door_sets": SHOPFRONT,
		"rooms": [
			{ "key": "stockroom", "type": "stockroom", "rect": Rect2(0, 0, 300, 220) },
			{ "key": "elevator_lobby", "type": "elevator_lobby", "rect": Rect2(300, 0, 240, 220) },
			{ "key": "noodle_bar", "type": "noodle_bar", "rect": Rect2(0, 220, 540, 300) },
		],
		"openings": [
			{ "pos": Vector2(270, 520), "width": 69.0, "front": true },  # noodle bar, shopfront
			{ "pos": Vector2(0, 110), "width": 69.0, "exit": true },  # stockroom, side door
			{ "pos": Vector2(150, 220), "width": 60.0 },  # noodle bar <-> stockroom
			{ "pos": Vector2(420, 220), "width": 60.0 },  # noodle bar <-> lobby
		],
	},
	# An arcade: a long hall on the street with a shop, the lobby and a noodle bar off it.
	"arcade_tower": {
		"wall_thickness": 12.0,
		"door_sets": STEEL_FRONT,
		"rooms": [
			{ "key": "shop", "type": "shop", "rect": Rect2(0, 0, 300, 220) },
			{ "key": "elevator_lobby", "type": "elevator_lobby", "rect": Rect2(300, 0, 240, 220) },
			{ "key": "noodle_bar", "type": "noodle_bar", "rect": Rect2(540, 0, 300, 220) },
			{ "key": "hallway", "type": "hallway", "rect": Rect2(0, 220, 840, 130) },
		],
		"openings": [
			{ "pos": Vector2(420, 350), "width": 69.0, "front": true },  # hallway, street door
			{ "pos": Vector2(150, 220), "width": 60.0 },  # hallway <-> shop
			{ "pos": Vector2(420, 220), "width": 60.0 },  # hallway <-> lobby
			{ "pos": Vector2(690, 220), "width": 60.0 },  # hallway <-> noodle bar
		],
	},
	# A clinic tower: a security vestibule on the street, the lobby above it, the ripperdoc beside
	# it and the netrunner's den at the back of the ripperdoc.
	"clinic_tower": {
		"wall_thickness": 12.0,
		"door_sets": STEEL_FRONT,
		"rooms": [
			{ "key": "elevator_lobby", "type": "elevator_lobby", "rect": Rect2(0, 0, 260, 200) },
			{ "key": "netrunner_den", "type": "netrunner_den", "rect": Rect2(260, 0, 380, 200) },
			{
				"key": "security_vestibule",
				"type": "security_vestibule",
				"rect": Rect2(0, 200, 260, 300),
			},
			{ "key": "ripperdoc", "type": "ripperdoc", "rect": Rect2(260, 200, 380, 300) },
		],
		"openings": [
			{ "pos": Vector2(130, 500), "width": 69.0, "front": true },  # vestibule, street door
			{ "pos": Vector2(130, 200), "width": 60.0 },  # vestibule <-> lobby
			{ "pos": Vector2(260, 350), "width": 60.0 },  # vestibule <-> ripperdoc
			{ "pos": Vector2(450, 200), "width": 60.0 },  # ripperdoc <-> den
		],
	},
	# A corner shop: the shop on the street, the lobby and a staff bathroom behind it.
	"corner_shop_tower": {
		"wall_thickness": 12.0,
		"door_sets": SHOPFRONT,
		"rooms": [
			{ "key": "elevator_lobby", "type": "elevator_lobby", "rect": Rect2(0, 0, 240, 200) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(240, 0, 320, 200) },
			{ "key": "shop", "type": "shop", "rect": Rect2(0, 200, 560, 300) },
		],
		"openings": [
			{ "pos": Vector2(200, 500), "width": 69.0, "front": true },  # shop, shopfront
			{ "pos": Vector2(120, 200), "width": 60.0 },  # shop <-> lobby
			{ "pos": Vector2(400, 200), "width": 60.0 },  # shop <-> bathroom
		],
	},
	# A food hall: a noodle bar on the street with a shop beside it, the lobby and a long stockroom
	# (with the back exit) behind them.
	"food_hall_tower": {
		"wall_thickness": 12.0,
		"door_sets": SHOPFRONT,
		"rooms": [
			{ "key": "elevator_lobby", "type": "elevator_lobby", "rect": Rect2(0, 0, 240, 200) },
			{ "key": "stockroom", "type": "stockroom", "rect": Rect2(240, 0, 500, 200) },
			{ "key": "noodle_bar", "type": "noodle_bar", "rect": Rect2(0, 200, 420, 300) },
			{ "key": "shop", "type": "shop", "rect": Rect2(420, 200, 320, 300) },
		],
		"openings": [
			{ "pos": Vector2(210, 500), "width": 69.0, "front": true },  # noodle bar, shopfront
			{ "pos": Vector2(740, 100), "width": 69.0, "exit": true },  # stockroom, back door
			{ "pos": Vector2(120, 200), "width": 60.0 },  # noodle bar <-> lobby
			{ "pos": Vector2(420, 350), "width": 60.0 },  # noodle bar <-> shop
			{ "pos": Vector2(580, 200), "width": 60.0 },  # shop <-> stockroom
		],
	},
}


## The tower plan for `key`, or {} if unknown.
static func get_plan(key: String) -> Dictionary:
	return PLANS.get(key, {})


## Every tower plan key.
static func get_all() -> Array:
	return PLANS.keys()
