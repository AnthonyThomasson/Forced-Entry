extends GameTest
## G3: a grenade bounces in 3D. Thrown at a point in the next room with no doorway between, a stun
## flies up to the wall in the air (the arc is still 50 px up or more where it arrives, it does not
## skid into the wall), bounces back off it, falls to the floor, bounces on that, and comes to rest
## on the floor on the thrower's side: the wall and the floor both bounce it, each posting a clatter
## (a `grenade` event, stage `bounce`), the floor's bounce keeps the restitution's share of the
## speed into it (`GrenadeConfig`'s 0.35), and at rest it lies on the floor with no speed.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const WALL_X := 400.0
const FROM := Vector2(250, 250)
const AIM := Vector2(600, 250)


func describe() -> Dictionary:
	return {
		"name": "A grenade bounces off a wall and the floor in 3D and comes to rest",
		"description": "A stun thrown at a point beyond a solid wall strikes the wall high in the "
			+ "air, falls to the floor, bounces again and lies still on the floor, nearer the "
			+ "thrower than the wall.",
		"tags": ["grenade", "bounce", "wall", "floor", "rest", "item", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 500) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(400, 0, 400, 500) },
	], [{ "pos": Vector2(600, 500), "width": 80.0 }])
	s.switch(&"nav.rebake", false)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun"):
		return
	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	var flight := await Probe.track(t, 4.0)
	if not t.require(flight.size() > 10, "a grenade flew"):
		return
	var struck_at := -1.0
	var resumed := -1
	for i in range(1, flight.size()):
		if struck_at < 0.0 and flight[i - 1]["at"].x > flight[i]["at"].x:
			struck_at = float(flight[i - 1]["altitude"])
			resumed = i
	t.require(struck_at >= 0.0, "premise: the grenade turned back")
	t.check(
		struck_at > 20.0,
		"it struck the wall in the air (%.0f px up), not along the floor" % struck_at,
	)
	var landings := 0
	var was_down := false
	for i in range(maxi(resumed, 1), flight.size()):
		var low: bool = float(flight[i]["altitude"]) < 1.0
		if low and not was_down:
			landings += 1
		was_down = low
	t.check(landings >= 1, "it fell back to the floor (%d landings after the wall)" % landings)
	var bounces := Probe.raw(t, &"grenade", func(d): return d.get("stage") == &"bounce")
	t.check(
		bounces.size() >= 2,
		"the wall and the floor each clattered (%d bounces)" % bounces.size(),
	)
	_check_restitution(t, flight, resumed)
	var last: Dictionary = flight.back()
	t.check(float(last["altitude"]) < 1.0, "at rest it lies on the floor")
	t.check(last["at"].x < WALL_X, "on the thrower's side of the wall (x %.0f)" % last["at"].x)
	var rests := Probe.raw(t, &"grenade", func(d): return d.get("stage") == &"rest")
	t.check(not rests.is_empty(), "it came to rest (a rest event)")


## The floor's bounce keeps the restitution's share of the speed into it: the speed it fell at (the
## last two frames before the floor, a frame and a bit of gravity on) against the speed it rose at
## (`sqrt(2 g h)` of the peak of the hop).
func _check_restitution(t: TestContext, flight: Array, resumed: int) -> void:
	var landed := -1
	for i in range(maxi(resumed, 2), flight.size()):
		if float(flight[i]["altitude"]) < 1.0:
			landed = i
			break
	if not t.require(landed >= 2, "premise: it fell to the floor after the wall"):
		return
	var dt: float = float(flight[landed - 1]["time"]) - float(flight[landed - 2]["time"])
	var gravity: float = GrenadeConfig.gravity
	var drop: float = float(flight[landed - 2]["altitude"]) - float(flight[landed - 1]["altitude"])
	var into: float = drop / dt + gravity * dt * 1.2
	var hop := 0.0
	for i in range(landed + 1, flight.size()):
		hop = maxf(hop, float(flight[i]["altitude"]))
		if float(flight[i]["altitude"]) < 0.01 and hop > 1.0:
			break
	var keep := float(GrenadeConfig.row(&"stun").get("restitution", 0.0))
	var out := sqrt(2.0 * gravity * hop)
	t.expect_near(
		out / into, keep, 0.06,
		"the floor's bounce keeps the restitution's share of the speed (%.2f of it)" % (out / into),
	)
