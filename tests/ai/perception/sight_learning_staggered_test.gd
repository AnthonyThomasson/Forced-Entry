extends GameTest
## A squad does not look for unknown rooms and furniture on one frame (`perception_house.gd`,
## `learn_by_sight`, #192 Extension 3). Twelve unfamiliar NPCs (the invader preset, Von down, held
## in place) learn by sight every `LEARN_EVERY_FRAMES` (6) physics frames, each on a phase of its
## own, so the looks spread over the cycle: no frame of it has more than ceil(12 / 6) = 2 of the
## scheduled looks. The phase is handed out in turn, not read off the perception node's instance
## id: ids step in fixed strides, so on a build where allocations fall that way nine of ten NPCs
## shared one phase, and any change to what the process allocates moved every NPC's phase (a
## match played another fight for it).

const PerceptionHouse := preload("res://scenes/ai/perception/perception_house.gd")
const COUNT := 12
## Physics frames in one learning cycle (`LEARN_EVERY_FRAMES`, 6) and the most scheduled looks one
## frame may hold: ceil(COUNT / 6).
const CYCLE := PerceptionHouse.LEARN_EVERY_FRAMES
const MOST_PER_FRAME := 2  # ceil(COUNT / CYCLE), by the spec's arithmetic
## Frames watched, after every NPC has had its first look.
const WATCH_FRAMES := 120
const SETTLE_S := 1.5


func describe() -> Dictionary:
	return {
		"name": "A squad's looks for the house are spread over frames",
		"description": "Twelve unfamiliar NPCs learn the house by sight every 6 frames; no frame "
			+ "holds more than 2 of their scheduled looks.",
		"tags": ["ai", "vision", "scripted", "perception"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.von_down()
	for i in COUNT:
		s.actor(
			StringName("inv%d" % i),
			&"invader",
			Vector2(100 + (i % 6) * 120, 150 + int(i / 6.0) * 200),
			{ "movement:speed": 0.0, "facing": Vector2.RIGHT },
		)
		# No decision inside the watch: its own look would move the NPC's phase.
		s.set_props(
			StringName("inv%d" % i),
			"GoalController",
			{ "tuning:decision:decide_interval": 100.0 },
		)


func run(t: TestContext) -> void:
	var houses: Array = []
	for i in COUNT:
		var perception: Object = t.controller(StringName("inv%d" % i), &"debug_room_zones") \
				.get("_perception")
		houses.append(perception.house)
	await t.seconds(SETTLE_S)
	var seen := _looks(houses)
	if not t.require(
			seen.min() > 0,
			"every NPC has made a scheduled look by now (%s)" % str(seen),
	):
		return
	var per_frame := {}
	var at_least := 0
	for f in WATCH_FRAMES:
		await t.frames(1)
		var now := _looks(houses)
		var made := 0
		for i in COUNT:
			made += now[i] - seen[i]
		seen = now
		per_frame[f] = made
		at_least = maxi(at_least, made)
	t.check(
		at_least <= MOST_PER_FRAME,
		"no frame holds more than %d scheduled looks (most in one frame: %d; by frame %s)"
			% [MOST_PER_FRAME, at_least, str(per_frame.values().slice(0, CYCLE * 2))],
	)
	t.check(
		per_frame.values().reduce(func(a: int, b: int) -> int: return a + b, 0)
				>= COUNT * (int(WATCH_FRAMES / float(CYCLE)) - 1),
		"the NPCs keep looking every cycle, not fewer looks to meet the bound",
	)


## How many scheduled looks each house has made so far (the sliced looks count only those: a
## decision's own look is a full one).
func _looks(houses: Array) -> Array:
	return houses.map(func(h: Object) -> int: return int(h.get("_sliced_looks")))
