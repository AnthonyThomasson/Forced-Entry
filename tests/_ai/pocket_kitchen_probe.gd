extends RefCounted
## Shared helper for the stack tests that need a stack standing in a tight pocket at a doorway of
## the house's own width (`docs/doors.md` DR1; not a test itself):
## `const Pocket := preload("res://tests/_ai/pocket_kitchen_probe.gd")`.
##
## A hand-laid kitchen (400 x 360, `KITCHEN`) with the doorway of a garage home's kitchen, `DOOR`,
## 60 px wide, on its north wall into a garage above it, a doorway of the same width on its west
## wall into a living room, and the front door on the living room's south wall. The kitchen is
## furnished so that no spot against the north wall east of the door holds a body (a run of counters
## and plants), and a fridge in the north-west corner closes the west run at about 80 px from the
## door: the stack going in from the kitchen forms in the west file, two against the wall and the
## rest a step out (`tests/ai/entry/stack_move_up_lets_follower_in`,
## `stack_move_up_keeps_slot_reachable`, `entry_last_leg_sealed_goes_round`). The starts are those
## of the garage home's tests: `NEAR` and `WRONG` by the door, `FAR` in the kitchen's far corner and
## `BEYOND` in the garage.

const KITCHEN := Rect2(300, -360, 400, 360)
const GARAGE := Rect2(280, -760, 420, 400)
const LIVING_ROOM := Rect2(-300, -360, 600, 360)
## The doorway from the kitchen into the garage.
const DOOR := Vector2(500, -360)
const DOOR_WIDTH := 60.0
const NEAR := Vector2(615, -295)
const WRONG := Vector2(420, -300)
const FAR := Vector2(660, -30)
const BEYOND := Vector2(380, -470)


## Declare the layout and its furniture on `s`; `sealed` adds the plant that, with the chairs, shuts
## the way under the west file's third slot to the pocket behind the first three.
static func layout(s: TestSetup, sealed := false) -> void:
	s.layout(
		[
			{ "key": "living_room", "type": "living_room", "rect": LIVING_ROOM },
			{ "key": "kitchen", "type": "kitchen", "rect": KITCHEN },
			{ "key": "garage", "type": "garage", "rect": GARAGE },
		],
		[
			{ "pos": Vector2(0, 0), "width": 69.0 },
			{ "pos": Vector2(300, -180), "width": DOOR_WIDTH },
			{ "pos": DOOR, "width": DOOR_WIDTH },
		],
	)
	# The north-west corner, the counter run and the island with its chairs in the middle.
	s.object(&"fridge", "fridge", Vector2(342, -313))
	s.object(&"counter_w", "kitchen_counter", Vector2(362, -37))
	s.object(&"stove", "stove", Vector2(439, -37))
	s.object(&"sink", "sink", Vector2(491, -37))
	s.object(&"counter_e", "kitchen_counter", Vector2(568, -37))
	s.object(&"island", "island", Vector2(500, -163))
	s.object(&"chair_w", "chair", Vector2(475, -210))
	s.object(&"chair_e", "chair", Vector2(525, -210))
	s.object(&"cabinet", "cabinet", Vector2(670, -233), { "rotated": true })
	s.object(&"microwave", "microwave", Vector2(668, -185))
	# Along the north wall east of the door: no spot against it holds a body.
	s.object(&"counter_north", "kitchen_counter", Vector2(582, -329))
	s.object(&"plant_a", "plant", Vector2(655, -335))
	s.object(&"plant_b", "plant", Vector2(683, -335))
	if sealed:
		# Closes the way under the third slot to the pocket behind the first three: the gap
		# between the second-file spot and the chairs.
		s.object(&"plant_d", "plant", Vector2(478, -246))
	else:
		# Keeps the east wall's second file out of the stack: no spot east of the door holds a body.
		s.object(&"plant_c", "plant", Vector2(548, -280))
