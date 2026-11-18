extends GameTest
## G8 (#194 D10): a grenade at rest on a piece does not hover when the piece under it goes: pushed
## away (or blasted off) before the fuse is out, it falls and bursts where it lies, on the floor
## (the burst announced at the floor's height, `Explosion.BURST_CENTRE` up), not at the height of
## a desk that is no longer there.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const DESK := Vector2(300, 100)
const FROM := Vector2(100, 100)


func describe() -> Dictionary:
	return {
		"name": "A frag falls when the desk it rests on is taken away",
		"description": "A frag rests on a desk; the desk is moved off it before the fuse is out: "
			+ "the frag falls and goes off on the floor, not at the desk's height.",
		"tags": ["grenade", "frag", "altitude", "3d"],
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
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag"):
		return
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
	# the desk is taken away from under it
	desk.global_position = Vector2(DESK.x, DESK.y + 150.0)
	if not t.require(
			await t.until(func(): return grenade.altitude() < 1.0, 1.0),
			"the grenade falls to the floor once the desk is gone (altitude %.1f px)"
				% grenade.altitude(),
	):
		return
	if not t.require(await Probe.wait_boom(t, &"frag", 4.0), "the frag went off"):
		return
	var height := float(Probe.raw(t, &"explosion")[0]["data"]["height"])
	t.expect_near(
		height,
		Explosion.BURST_CENTRE,
		1.5,
		"and the burst is at the floor's height (%.1f px)" % height,
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
