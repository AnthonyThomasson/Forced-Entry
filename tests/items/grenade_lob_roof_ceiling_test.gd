extends GameTest
## G3, D11a: only a real ceiling caps a lob. Two throwers lob 420 px at a point 105 px past a
## wardrobe (78 px tall, 90 wide) 270 px from them. A steep drop behind it needs an arc
## peaking over 96 px: under a roof (a room's) there is none, the grenade strikes the wardrobe (or
## the roof) and does not land at the aim; in the open (no roof) the apex goes as high as
## `GrenadeConfig.max_apex` and the grenade clears the wardrobe, over the walls' height, and lands
## at the aim.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const ROOM := Rect2(0, 0, 700, 400)
## Each lane: thrower, wardrobe (90 x 45, top 78) and aim along y = 200.
const IN_FROM := Vector2(80, 200)
const IN_WARDROBE := Vector2(350, 200)
const IN_AIM := Vector2(500, 200)
const OUT_FROM := Vector2(980, 200)
const OUT_WARDROBE := Vector2(1250, 200)
const OUT_AIM := Vector2(1400, 200)
const WALLS := 96.0


func describe() -> Dictionary:
	return {
		"name": "A lob is capped by a roof, and only by one",
		"description": "A steep drop behind a wardrobe: in a roofed room the grenade cannot rise "
			+ "over the walls' height and does not land at the aim; in the open it peaks higher "
			+ "than the walls and lands at the aim.",
		"tags": ["grenade", "lob", "roof", "item", "3d"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "room", "type": "living_room", "rect": ROOM }], [])
	s.switch(&"nav.rebake", false)
	s.object(&"in_wardrobe", "wardrobe", IN_WARDROBE)
	s.object(&"out_wardrobe", "wardrobe", OUT_WARDROBE)
	s.actor(&"indoor", &"puppet", IN_FROM, { "max_health": 100_000.0 })
	s.actor(&"outdoor", &"puppet", OUT_FROM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	for who in [&"indoor", &"outdoor"]:
		Probe.arm(t.actor(who), 1, 0)
	var peaks := { &"in": 0.0, &"out": 0.0 }
	await Probe.throw_at(t, &"outdoor", Probe.STUN, OUT_AIM)
	await _watch(t, peaks, &"out", 1)
	var out_rest := _burst_of(t, 1)
	t.check(
		peaks[&"out"] > WALLS,
		"in the open the lob peaked over the walls' height (%.0f px)" % peaks[&"out"],
	)
	t.check(
		out_rest.distance_to(OUT_AIM) < 45.0,
		"and landed at the aim behind the wardrobe (%.0f px off)" % out_rest.distance_to(OUT_AIM),
	)
	await Probe.throw_at(t, &"indoor", Probe.STUN, IN_AIM)
	await _watch(t, peaks, &"in", 2)
	var in_rest := _burst_of(t, 2)
	t.check(
		peaks[&"in"] <= WALLS,
		"under a roof the lob stayed under the walls' height (%.0f px)" % peaks[&"in"],
	)
	t.check(
		in_rest.distance_to(IN_AIM) > 45.0,
		"and did not land at the aim (%.0f px off)" % in_rest.distance_to(IN_AIM),
	)


## Follow the grenade until the `booms`th stun goes off, keeping the highest its underside went.
func _watch(t: TestContext, peaks: Dictionary, key: StringName, booms: int) -> void:
	var until := t.time + 8.0
	while t.time < until:
		await t.frames(1)
		for g: Node in Probe.live(t):
			peaks[key] = maxf(peaks[key], float(g.call("altitude")))
		if Probe.booms(t, &"stun").size() >= booms:
			break


## Where the `n`th stun went off.
func _burst_of(t: TestContext, n: int) -> Vector2:
	var booms := Probe.booms(t, &"stun")
	return booms[n - 1]["data"]["position"] if booms.size() >= n else Vector2.INF
