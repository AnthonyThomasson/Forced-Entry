extends GameTest
## G8 (#194 D10): a frag that comes to rest on a vehicle's roof bursts at the roof's height, not at
## the floor under the van: the burst the explosion event announces is at the grenade's own altitude
## plus the burst's centre (`Explosion.BURST_CENTRE`), and the fragments leave from there.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const VAN := Vector2(330, 150)
const FROM := Vector2(100, 150)


func describe() -> Dictionary:
	return {
		"name": "A frag lying on a van's roof bursts at the roof's height",
		"description": "A frag thrown onto a van comes to rest on its roof and goes off there: "
			+ "the burst is announced well above the floor, at the grenade's altitude.",
		"tags": ["grenade", "frag", "altitude", "vehicle", "3d"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 300))
	s.switch(&"nav.rebake", false)
	s.vehicle(&"van", &"van", VAN)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag"):
		return
	await Probe.throw_at(t, &"thrower", Probe.FRAG, VAN)
	if not t.require(
			await t.until(func(): return not Probe.live(t).is_empty(), 3.0),
			"the grenade is in flight",
	):
		return
	var grenade: Node = Probe.live(t)[0]
	var at_rest := -1.0
	while t.time < 8.0 and is_instance_valid(grenade) and grenade.fuse_left() > 0.05:
		at_rest = float(grenade.altitude())
		await t.frames(1)
	if not t.require(await Probe.wait_boom(t, &"frag", 2.0), "the frag went off"):
		return
	var height := float(Probe.raw(t, &"explosion")[0]["data"]["height"])
	t.check(at_rest > 20.0, "it lay on the roof, well over the floor (%.1f px)" % at_rest)
	t.expect_near(
		height,
		at_rest + Explosion.BURST_CENTRE,
		1.5,
		"and the burst is announced at that height (%.1f px)" % height,
	)
