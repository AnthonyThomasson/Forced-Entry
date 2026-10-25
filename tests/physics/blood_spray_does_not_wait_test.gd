extends GameTest
## A hit's spray (`BloodWound.record`) begins its splats (their shapes and wall rays on the main
## thread, their outlines merged on worker threads) and returns without waiting for the merges, so
## the rest of the frame's work runs beside them. Nothing sees a splat unfinished: its wet highlight
## and its drying start at the hit, any read of the blood field finishes every pending splat before
## it answers, and the frame finishes the rest before it is drawn, each aged from the hit's physics
## frame as if finished at once.

const SEED := 7878


func describe() -> Dictionary:
	return {
		"name": "A spray does not wait for its merges",
		"description": "BloodWound.record returns with its splats' merges still running; a blood "
			+ "field read, or the frame's end, finishes them, aged from the hit.",
		"tags": ["blood", "splat", "threads"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"physics.blood", true)
	s.switch(&"nav.rebake", false)
	s.set_static(BloodWound, &"spray_side_by_side", true)
	s.actor(&"victim", &"puppet", Vector2(300, 200), { "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	await t.frames(2)
	var victim := t.actor(&"victim")
	var wound: BloodWound = victim.anatomy.wound
	seed(SEED)

	# Read in the same frame: the read finishes the spray first.
	var made := _spray(wound, victim, 0)
	if not t.require(made.size() >= 3, "the hit threw splats (%d)" % made.size()):
		return
	var unfinished := made.filter(func(s): return s.shapes.is_empty()).size()
	t.check(unfinished > 0, "record returned before its splats' merges were done (%d of %d)"
		% [unfinished, made.size()])
	t.check(
		made.all(func(s): return (s.get_node_or_null("Highlight") != null) == (s._radius >= 2.0)),
		"each splat's wet highlight (a splat 2 px or more across) is there from the hit",
	)
	var wet := BloodField.wetness_at(made[0].global_position)
	t.check(wet > 0.0, "a blood field read in the same frame finds the new blood (%.2f)" % wet)
	t.check(
		made.all(func(s): return not s.shapes.is_empty() and s._task < 0),
		"the read finished every pending splat first",
	)

	# Nothing reads: the frame finishes them, aged from the hit's physics frame.
	var frame := Engine.get_physics_frames()
	var later := _spray(wound, victim, 1)
	await t.frames(1)
	t.check(
		later.all(func(s): return not s.shapes.is_empty() and s._task < 0),
		"by the next frame every splat is finished",
	)
	var born: Array = []
	for splat in later:
		var entry: Dictionary = BloodField._splats.get(splat.get_instance_id(), {})
		born.append(entry.get("born", -1))
	t.check(born.all(func(b): return b == frame),
		"each is aged from the hit's physics frame %d (%s)" % [frame, born])


## Strike the victim once (hit `k`) and return the splats its wound threw.
static func _spray(wound: BloodWound, victim: Node2D, k: int) -> Array:
	var hit := HitInfo.new()
	hit.normal = Vector2.from_angle(k * 1.3)
	hit.direction = -hit.normal
	hit.position = victim.global_position + hit.normal * 10.0
	hit.damage = 40.0
	hit.has_exit = true
	hit.exit_position = victim.global_position - hit.normal * 10.0
	var before: int = wound._splats.size()
	wound.record(hit)
	return wound._splats.slice(before)
