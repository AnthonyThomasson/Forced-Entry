extends GameTest
## G2 / G3: a grenade aimed at a spot just behind low cover is lobbed over it. A throw touches down
## short of its aim and skids the rest of the way, so a sofa between the touchdown and the aim would
## stop the skid and kick the grenade back toward the thrower; the planner (`GrenadeArc`) finds the
## arc that goes over the sofa (38 px at its tallest) to touch down past it, and the grenade rolls
## on a little past the aim (as a throw aimed past `max_range` does). A sofa stood on end across the
## lane 50 px in front of the aim: the grenade first touches down beyond the sofa, and ends on the
## far side of it, within that roll of the aim.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(100, 150)
## stood on end: 50 px deep along the lane, 120 px across it
const SOFA := Vector2(430, 150)
## its face away from the thrower
const SOFA_FAR_FACE := 455.0
## 25 px past that face, 380 px from the thrower: in range
const AIM := Vector2(480, 150)
## how far past its aim a lob that touches down beyond it may roll (G2)
const ROLL_ON := 100.0


func describe() -> Dictionary:
	return {
		"name": "A grenade aimed behind a sofa comes to rest behind it",
		"description": "Thrown at a point just past a sofa standing across the lane, a stun "
			+ "grenade flies over the sofa's top and comes to rest on its far side, a roll past "
			+ "the aim, instead of skidding into it and bouncing back.",
		"tags": ["grenade", "lob", "cover", "item"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"sofa", "sofa", SOFA, { "rotated": true })
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(
			Probe.count(thrower, Probe.STUN) == 1,
			"the thrower carries a stun grenade (Character.inventory.item_count(7) = %d)"
				% Probe.count(thrower, Probe.STUN),
	):
		return
	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	var flight := await Probe.track(t, 4.0)
	if not t.require(flight.size() > 10, "a grenade flew"):
		return
	var clatters := Probe.raw(t, &"grenade", func(d): return d.get("stage") == &"bounce")
	t.require(not clatters.is_empty(), "premise: it bounced")
	var first: float = clatters[0]["data"]["position"].x
	t.check(
		first > SOFA_FAR_FACE,
		"it flew over the sofa and first touched down beyond it (x %.0f, the far face at %.0f)"
			% [first, SOFA_FAR_FACE],
	)
	var rest: Vector2 = flight.back()["at"]
	t.check(
		rest.x > SOFA_FAR_FACE,
		"it came to rest on the far side of the sofa (x %.0f, the far face at %.0f)"
			% [rest.x, SOFA_FAR_FACE],
	)
	t.check(
		rest.distance_to(AIM) < ROLL_ON,
		"within a roll of the aim point (%.0f px off)" % rest.distance_to(AIM),
	)
