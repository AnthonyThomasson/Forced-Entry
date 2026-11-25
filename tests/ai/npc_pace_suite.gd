extends UnitSuite
## Native unit suite (pure logic): an NPC's beat (`npc_pace.gd`). One frame in `BEAT` on the phase
## of its spawn order (`WorldRng`), the frames between carried to the next beat as owed seconds, a
## wake at once whatever the frame, and a squad of NPCs split evenly over the two phases.

const Pace := preload("res://scenes/ai/npc_pace.gd")
const NPCS := 6
## NPCs on the beat of any one frame: half.
const NPCS_ON := 3
const DT := 0.016


## A world of `NPCS` enrolled characters, each with a bound beat; returns `[bodies, paces]`.
func _squad() -> Array:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	WorldRng.register(root, 0)
	var bodies: Array = []
	var paces: Array = []
	for i in NPCS:
		var body: Node2D = auto_free(Node2D.new())
		root.add_child(body)
		WorldRng.enrol(body)
		var pace: RefCounted = Pace.new()
		pace.bind(body)
		bodies.append(body)
		paces.append(pace)
	return [bodies, paces]


func test_an_npc_beats_one_frame_in_beat_on_its_spawn_order_phase() -> void:
	var squad := _squad()
	var bodies: Array = squad[0]
	var paces: Array = squad[1]
	for n in NPCS:
		for frame in 8:
			assert_bool(paces[n].on_beat(frame)) \
				.override_failure_message("npc %d frame %d" % [n, frame]) \
				.is_equal((frame + n) % Pace.BEAT == 0)
	assert_int(bodies.size()).is_equal(NPCS)


func test_a_squad_splits_evenly_over_the_phases() -> void:
	var squad := _squad()
	var paces: Array = squad[1]
	for frame in 6:
		var on := 0
		for pace in paces:
			on += 1 if pace.on_beat(frame) else 0
		assert_int(on).override_failure_message("frame %d" % frame).is_equal(NPCS_ON)


func test_a_coast_carries_its_seconds_to_the_next_beat() -> void:
	var pace: RefCounted = _squad()[1][0]  # spawn order 0: its beats are the even frames
	var seen: Array = []
	for frame in 6:
		seen.append(pace.step(frame, DT, false))
	assert_array(seen.map(func(s: float) -> bool: return s >= 0.0)) \
		.is_equal([true, false, true, false, true, false])
	assert_float(seen[0]).is_equal_approx(DT, 0.0001)
	assert_float(seen[2]).is_equal_approx(DT * 2.0, 0.0001)
	assert_float(pace.owed).is_equal_approx(DT, 0.0001)
	assert_int(pace.beats).is_equal(3)
	assert_int(pace.coasts).is_equal(3)


func test_awake_runs_the_beat_at_once_with_what_it_owes() -> void:
	var pace: RefCounted = _squad()[1][0]
	assert_float(pace.step(0, DT, false)).is_equal_approx(DT, 0.0001)
	assert_float(pace.step(1, DT, false)).is_less(0.0)
	assert_float(pace.step(1, DT, true)).is_equal_approx(DT * 2.0, 0.0001)
	assert_float(pace.owed).is_equal(0.0)
	# The phase is not moved: a frame 1 woken, frame 2 is a beat on its own turn and frame 3 a
	# coast, as if it had never been woken.
	assert_float(pace.step(2, DT, false)).is_greater(0.0)
	assert_float(pace.step(3, DT, false)).is_less(0.0)
