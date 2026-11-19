extends GameTest
## A grenade at rest on a piece falls when the piece tips (#194 furn3d, D13/D14): the piece is a
## free 3D body, so what rests on it loses its support as it goes over and bursts where it lies, on
## the floor, not at the height of the desk it was on.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const ObjectProbe := preload("res://tests/_objects/piece_probe.gd")
const DESK := Vector2(300, 100)
const FROM := Vector2(100, 100)


func describe() -> Dictionary:
	return {
		"name": "A frag on a desk falls when the desk tips over",
		"description": "A frag rests on a desk; the desk is knocked over before the fuse is "
			+ "out: the frag falls with it and goes off low, not at the desk's height.",
		"tags": ["grenade", "frag", "altitude", "3d", "tipping", "furniture"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"desk", "desk", DESK)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var desk := t.object(&"desk")
	Probe.arm(thrower, 0, 1)
	await Probe.throw_at(t, &"thrower", Probe.FRAG, DESK)
	if not t.require(
			await t.until(func(): return not Probe.live(t).is_empty(), 3.0),
			"the grenade is in flight",
	):
		return
	var grenade: Node = Probe.live(t)[0]
	if not t.require(
			await _lies_still_on_top(t, grenade),
			"set-up: it came to rest on the desk's top with the fuse still running",
	):
		return
	var resting: float = grenade.altitude()
	# knocked over: a hard shove near the top
	Knockback.push(desk, Vector2(0.0, 40_000.0), Vector2.ZERO, ObjectProbe.top(desk) - 2.0)
	if not t.require(
			await t.until(func(): return ObjectProbe.lean(desk) > 45.0, 2.0),
			"premise: the desk goes over",
	):
		return
	if not t.require(
			await t.until(func(): return grenade.altitude() < resting - 15.0, 2.0),
			"the grenade comes down with it (altitude %.1f px from %.1f)"
				% [grenade.altitude(), resting],
	):
		return
	if not t.require(await Probe.wait_boom(t, &"frag", 4.0), "the frag went off"):
		return
	var height := float(Probe.raw(t, &"explosion")[0]["data"]["height"])
	t.check(
		height < resting - 15.0,
		"and the burst is low (%.1f px), not at the desk's height (%.1f)" % [height, resting],
	)


## Wait until `grenade` has not moved for 15 frames while its fuse is over 0.8 s: whether it then
## lies at least 20 px up (a desk's top).
func _lies_still_on_top(t: TestContext, grenade: Node) -> bool:
	var last := Vector2.INF
	var still := 0
	while t.time < 6.0 and is_instance_valid(grenade) and grenade.fuse_left() > 0.8:
		still = still + 1 if grenade.global_position == last else 0
		last = grenade.global_position
		if still >= 15:
			return grenade.altitude() > 20.0
		await t.frames(1)
	return false
