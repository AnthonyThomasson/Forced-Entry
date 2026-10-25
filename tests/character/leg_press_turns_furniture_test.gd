extends GameTest
## A leg pressing a light piece shoves it at the foot or knee, not at its centre (issue #50). Two
## crouched puppets walk slowly south toward the north side of a bench lying east-west, one near its
## east end and one near its west end. A crouch stands the feet ahead of the pelvis with the knees
## leading (standing, a stride reaches only ~1.5 px past the body circle), so the legs reach the
## bench well before the body and, at this pace, keep it ahead of the body: the leg press alone must
## turn the bench the way the pressed end is driven (east end: clockwise, a positive rotation; west
## end: counter-clockwise). Only what happens before the body first touches the bench is judged, so
## the walking push plays no part.

## A bench is 80 x 30; its long axis lies east-west.
const HALF_LENGTH := 40.0
const HALF_DEPTH := 15.0
## How far from the bench's centre each walker walks along it: 12 px in from an end.
const END_OFFSET := 28.0
const BODY_RADIUS := 14.0
## Px between a walker's body and the bench's north side at the start.
const START_GAP := 30.0
## A slow walk (a fraction of the crouched pace): the legs still stride, and the bench, shoved by
## them, keeps ahead of the body.
const WALK_INPUT := 0.3
const WALK_TIME := 3.0
## Time for the body to fold into its crouch before walking (s).
const CROUCH_TIME := 1.0
const EAST_BENCH := Vector2(250, 200)
const WEST_BENCH := Vector2(550, 200)
## A noticeable turn (degrees).
const MIN_TURN := 5.0


func describe() -> Dictionary:
	return {
		"name": "Leg press near one end turns a bench",
		"description": "Crouched puppets walk slowly at a bench near its east and its west end; "
			+ "the legs press it before the body touches it and turn it the way the pressed end "
			+ "is driven.",
		"tags": ["legs", "walk", "crouch", "pushable", "physics", "pivot"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.switch(&"nav.rebake", false)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	var walker_y := EAST_BENCH.y - HALF_DEPTH - BODY_RADIUS - START_GAP
	s.object(&"east_bench", "bench", EAST_BENCH)
	s.actor(
		&"east_walker",
		&"puppet",
		Vector2(EAST_BENCH.x + END_OFFSET, walker_y),
		{ "start_slot": 1 },
	)
	s.object(&"west_bench", "bench", WEST_BENCH)
	s.actor(
		&"west_walker",
		&"puppet",
		Vector2(WEST_BENCH.x - END_OFFSET, walker_y),
		{ "start_slot": 1 },
	)


func run(t: TestContext) -> void:
	var cases := [
		Press.new(&"east_walker", &"east_bench", 1.0),
		Press.new(&"west_walker", &"west_bench", -1.0),
	]
	for c: Press in cases:
		var bench: Node2D = t.object(c.bench)
		c.start = bench.global_position
		c.angle = bench.global_rotation
		t.puppet(c.walker).aim_at(t.actor(c.walker).global_position + Vector2(0, 1000))
		t.puppet(c.walker).set_posture(&"crouch")
	await t.seconds(CROUCH_TIME)
	for c: Press in cases:
		t.puppet(c.walker).walk(Vector2.DOWN * WALK_INPUT)
	var elapsed := 0.0
	while elapsed < WALK_TIME:
		await t.frames(1)
		elapsed += 1.0 / 60.0
		for c: Press in cases:
			_sample(t, c)
	for c: Press in cases:
		if not _check_press(t, c):
			return


## Trace one frame of `c`'s walk into its bench, and until the body touches it, how far the bench
## has moved and turned.
func _sample(t: TestContext, c: Press) -> void:
	var bench: Node2D = t.object(c.bench)
	var gap := _body_gap(t.actor(c.walker), bench)
	t.trace("%s_gap" % c.bench, gap)
	t.trace(
		"%s_turn_deg" % c.bench,
		rad_to_deg(angle_difference(c.angle, bench.global_rotation)),
	)
	if c.touched:
		return
	if gap <= 0.5:
		c.touched = true
		return
	c.moved = bench.global_position - c.start
	c.turn = rad_to_deg(angle_difference(c.angle, bench.global_rotation))


## Before the body touched it, `c`'s leg press shoved its bench south and turned it the way the
## pressed end is driven. Whether it was shoved (false after a failed `require`).
func _check_press(t: TestContext, c: Press) -> bool:
	var shoved: Vector2 = c.moved
	if not t.require(
			shoved.y > 2.0,
			"a foot pressed %s south before the body touched it (dy %.1f)" % [c.bench, shoved.y],
	):
		return false
	t.check(
		c.turn * c.sense > MIN_TURN,
		"the leg press turned %s %s before the body touched it (turned %.1f deg, want %s %.0f)"
			% [
				c.bench,
				"clockwise" if c.sense > 0.0 else "counter-clockwise",
				c.turn,
				">" if c.sense > 0.0 else "<",
				MIN_TURN * c.sense,
			],
	)
	return true


## Px between `walker`'s body circle and `bench`'s rectangle (0 or less: touching).
func _body_gap(walker: Node2D, bench: Node2D) -> float:
	var local := bench.to_local(walker.global_position)
	var nearest := Vector2(
		clampf(local.x, -HALF_LENGTH, HALF_LENGTH),
		clampf(local.y, -HALF_DEPTH, HALF_DEPTH),
	)
	return local.distance_to(nearest) - BODY_RADIUS


## One walker pressing its bench: the way the pressed end is driven (`sense`: 1 clockwise, -1
## counter-clockwise), where the bench started and how it lay, and how far it had moved and turned
## (deg) on the last frame before the body touched it.
class Press:
	var walker: StringName
	var bench: StringName
	var sense: float
	var start := Vector2.ZERO
	var angle := 0.0
	var moved := Vector2.ZERO
	var turn := 0.0
	var touched := false

	func _init(walker_id: StringName, bench_id: StringName, turn_sense: float) -> void:
		walker = walker_id
		bench = bench_id
		sense = turn_sense
