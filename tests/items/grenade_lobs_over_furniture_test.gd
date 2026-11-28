extends GameTest
## G3: the grenade flies a real 3D arc over what stands in its way. The planner (`GrenadeArc`) takes
## the lowest arc that clears the furniture's real top, so a desk (31 px) and a wardrobe (78 px),
## both under the highest lob (90 px), are flown over and the grenade lands at the aim point beyond
## them. Two throwers aim 400 px along parallel lanes: one over a desk, one over a wardrobe near
## the thrower; each grenade flies over its piece (its altitude over the piece is above the
## piece's top) and comes to rest at the aim.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
## 120 x 50, top 31
const DESK := Vector2(300, 100)
## 90 x 45, top 78: the highest lob (90 px) is over it only for a stretch of its flight, so it
## stands
## close to the thrower, where the arc is in that stretch
const WARDROBE := Vector2(220, 400)
const LANE_A := Vector2(100, 100)
const LANE_B := Vector2(100, 400)
const AIM_A := Vector2(500, 100)
const AIM_B := Vector2(500, 400)
const DESK_TOP := 31.0
const WARDROBE_TOP := 78.0


func describe() -> Dictionary:
	return {
		"name": "A grenade is lobbed over a desk and over a wardrobe",
		"description": "Two throwers aim 400 px along parallel lanes: the one with a desk across "
			+ "the lane and the one with a wardrobe across it each fly their grenade over the "
			+ "piece, higher than its top, and land at the aim point beyond it.",
		"tags": ["grenade", "lob", "cover", "item", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 500))
	s.switch(&"nav.rebake", false)
	s.object(&"desk", "desk", DESK)
	s.object(&"wardrobe", "wardrobe", WARDROBE)
	s.actor(&"over", &"puppet", LANE_A, { "max_health": 100_000.0 })
	s.actor(&"into", &"puppet", LANE_B, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	for who in [&"over", &"into"]:
		Probe.arm(t.actor(who), 2, 0)
	if not t.require(
			Probe.count(t.actor(&"over"), Probe.STUN) == 2
				and Probe.count(t.actor(&"into"), Probe.STUN) == 2,
			"both carry stun grenades",
	):
		return
	t.puppet(&"over").select_slot(Probe.STUN)
	t.puppet(&"into").select_slot(Probe.STUN)
	t.puppet(&"over").aim_at(AIM_A)
	t.puppet(&"into").aim_at(AIM_B)
	await t.seconds(0.4)
	t.puppet(&"over").shoot()
	t.puppet(&"into").shoot()
	var cleared := { &"desk": 0.0, &"wardrobe": 0.0 }
	var done := func() -> bool:
		_sample(t, cleared)
		return Probe.booms(t, &"stun").size() >= 2
	if not t.require(await t.until(done, 6.0), "both grenades go off"):
		return
	var lane_a: Vector2 = Vector2.INF
	var lane_b: Vector2 = Vector2.INF
	for b in Probe.booms(t, &"stun"):
		var p: Vector2 = b["data"]["position"]
		if p.y < 250.0:
			lane_a = p
		else:
			lane_b = p
	t.check(
		cleared[&"desk"] > DESK_TOP,
		"over the desk: it flew higher than its top (%.0f px up, the top at %.0f)"
			% [cleared[&"desk"], DESK_TOP],
	)
	t.check(
		cleared[&"wardrobe"] > WARDROBE_TOP,
		"over the wardrobe: it flew higher than its top (%.0f px up, the top at %.0f)"
			% [cleared[&"wardrobe"], WARDROBE_TOP],
	)
	t.check(
		lane_a.x > DESK.x + 60.0 and lane_a.distance_to(AIM_A) < 45.0,
		"it landed at the aim point past the desk (%.0f px off)" % lane_a.distance_to(AIM_A),
	)
	t.check(
		lane_b.x > WARDROBE.x + 45.0 and lane_b.distance_to(AIM_B) < 45.0,
		"and past the wardrobe (%.0f px off)" % lane_b.distance_to(AIM_B),
	)


## Raise `cleared` to the highest each grenade has been over each piece's footprint.
func _sample(t: TestContext, cleared: Dictionary) -> void:
	for grenade: Node in Probe.live(t):
		var at: Vector2 = grenade.global_position
		if absf(at.x - DESK.x) <= 60.0 and absf(at.y - DESK.y) <= 25.0:
			cleared[&"desk"] = maxf(cleared[&"desk"], grenade.altitude())
		if absf(at.x - WARDROBE.x) <= 45.0 and absf(at.y - WARDROBE.y) <= 22.5:
			cleared[&"wardrobe"] = maxf(cleared[&"wardrobe"], grenade.altitude())
