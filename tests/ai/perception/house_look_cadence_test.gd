extends GameTest
## The house look of an NPC's perception (`perception_house.gd`, `learn_by_sight`) in a world over
## physics frames: a squad's first looks land on every phase of the cycle in turn, whatever the
## process allocated between them; a scheduled look takes a third of the unknown furniture in view
## and a decision's own look all of it; and furniture in view is learned within eighteen frames of
## the first look, looking as `observe()` schedules it.

const Probe := preload("res://tests/_ai/cadence_probe.gd")
const SightBody := preload("res://tests/_ai/sight_body_probe.gd")
const PerceptionHouse := preload("res://scenes/ai/perception/perception_house.gd")
## NPCs in the squad case, and the allocation paddings it tries.
const SQUAD := 12
const PADS := 6
## Pieces of furniture in view, and the frames the schedule case watches.
const PIECES := 6
const WATCH_FRAMES := 30
## Frames from the first look to every piece learned (three looks of six frames).
const LEARN_FRAMES := 18

var _made: Array[Node] = []


func describe() -> Dictionary:
	return {
		"name": "A perception's house looks hold over frames in a world",
		"description": "A squad's first looks fill the cycle's phases evenly; a scheduled look "
			+ "takes a third of the unknown furniture, a decision's look all of it; furniture in "
			+ "view is learned within 18 frames of the first look.",
		"tags": ["ai", "perception", "vision"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"lighting.enabled", false)


func run(t: TestContext) -> void:
	_squad_looks_land_on_different_frames(t)
	await _looks_for_a_third_each_time(t)
	await _decisions_look_is_full(t)
	await _furniture_learned_within_eighteen_frames(t)
	for node in _made:
		node.free()


func _squad_looks_land_on_different_frames(t: TestContext) -> void:
	# Spaced by `pad` objects, the perceptions' instance ids step by a stride a remainder of six
	# can make equal for every one (pad 2): the phases must not follow it.
	var held: Array = []
	for pad in PADS:
		var frame := Engine.get_physics_frames()
		var first_looks := {}
		for n in SQUAD:
			var perception := Probe.perception()
			_made.append(perception)
			for p in pad:
				held.append(RefCounted.new())
			var body := SightBody.new()
			t.world.add_child(body)
			perception.set("_character", body)
			perception.house.learn_by_sight()
			var next: int = perception.house.learn_next
			t.check(
				next > frame and next <= frame + PerceptionHouse.LEARN_EVERY_FRAMES,
				"pad %d perception %d: next look at +%d" % [pad, n, next - frame],
			)
			var phase: int = next % PerceptionHouse.LEARN_EVERY_FRAMES
			first_looks[phase] = int(first_looks.get(phase, 0)) + 1
		# Twelve over six phases: two on each, the most the squad can be spread to.
		t.expect_eq(
			first_looks.values(),
			[2, 2, 2, 2, 2, 2],
			"pad %d: looks per phase %s" % [pad, str(first_looks)],
		)


func _looks_for_a_third_each_time(t: TestContext) -> void:
	var perception := Probe.perception_of(t.world, SightBody.new())
	_made.append(perception)
	perception.house.interactables = Probe.furniture(t.world, PIECES)
	var learned: Array[int] = []
	for look in 3:
		await t.frames(1)
		perception.house.learn_by_sight()
		learned.append(perception.house.known_object_ids().size())
	# A look takes at most a third of the pieces (rounded up), and three looks cover them all, so a
	# piece in view is learned at most three looks (18 frames) after it comes into view.
	t.check(learned[0] >= 1 and learned[0] <= 2, "the first look learns one or two pieces")
	t.check(
		learned[1] - learned[0] >= 1 and learned[1] - learned[0] <= 2,
		"the second look learns one or two more",
	)
	t.expect_eq(learned[2], PIECES, "three looks cover every piece")


func _decisions_look_is_full(t: TestContext) -> void:
	var perception := Probe.perception_of(t.world, SightBody.new())
	_made.append(perception)
	perception.house.interactables = Probe.furniture(t.world, PIECES)
	await t.frames(1)
	perception.house.learn_by_sight()
	t.check(perception.house.known_object_ids().size() < PIECES, "a scheduled look is partial")
	# The decision's own look, in the same frame as the scheduled one, covers every piece in view.
	perception.house.learn_by_sight(true)
	t.expect_eq(
		perception.house.known_object_ids().size(),
		PIECES,
		"a decision's look covers every piece in view",
	)


func _furniture_learned_within_eighteen_frames(t: TestContext) -> void:
	var perception := Probe.perception_of(t.world, SightBody.new())
	_made.append(perception)
	perception.house.interactables = Probe.furniture(t.world, PIECES)
	var first := -1
	var done := -1
	for frame in WATCH_FRAMES:
		await t.frames(1)
		# As the perception's observe() schedules it: a look once `learn_next` has come.
		if Engine.get_physics_frames() >= perception.house.learn_next:
			if first < 0:
				first = Engine.get_physics_frames()
			perception.house.learn_by_sight()
		if done < 0 and perception.house.known_object_ids().size() == PIECES:
			done = Engine.get_physics_frames()
	t.check(done > -1, "every piece in view was learned")
	t.check(
		done - first <= LEARN_FRAMES,
		"learned within %d frames (%d)" % [LEARN_FRAMES, done - first],
	)
