extends GameTest
## G17, the dropping rule for the thrower (tag `no_safe_spot`, in the tactic's `drop_tags`):
## GRENADE is not offered when the thrower would itself be inside the zone and has no way to get
## safe before the fuse runs out: no piece of furniture to shield it (G7, the real 3D line: a
## ducked hostile's cover shadows a thrower, so such a case is rare), no spot out of the burst's
## line within reach. A householder stands in the kitchen, in the open, in line with the back
## doorway; an invader with a frag stands in the garden in line with the doorway, 280 px from the
## burst (inside a frag's 370 px zone), with nothing to hide behind and held in place (`movement:
## speed` 0: it cannot walk to the wall beside the doorway, which would shield it). GRENADE is not
## offered, the option is tagged `no_safe_spot` and nothing is thrown. Given its legs back, the
## same invader has the wall to reach in the 3 s of the fuse: the option is not tagged and GRENADE
## is offered. Scripted Von; the householder is a puppet that cannot be killed and never shoots.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Hiding := preload("res://tests/_ai/hiding_piece.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const Spot := preload("res://tests/_ai/throw_spot_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const INVADER_AT := Vector2(980, 190)
const HOSTILE_AT := Vector2(700, 190)
## The invader's walking speed when it has its legs back.
const SPEED := 200.0


func describe() -> Dictionary:
	return {
		"name": "A grenade is not offered when the thrower has no way to get safe",
		"description": "An invader with a frag, held in the open in line with a doorway 280 px "
			+ "from a householder inside, has no safe place before the fuse is out: GRENADE is "
			+ "dropped and the option tagged no_safe_spot; free to walk to the wall beside the "
			+ "doorway, it is offered.",
		"tags": ["ai", "grenade", "combat", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Hiding.von_out(s)
	Maps.house(s, false)
	Flank.rules(
		s,
		[{ "pick": "combat" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }],
	)
	Flank.npc(s, &"n", INVADER_AT, {}, { "look_at": HOSTILE_AT })
	GrenadeAi.hostile(s, &"h", HOSTILE_AT, INVADER_AT)


func run(t: TestContext) -> void:
	var n := t.actor(&"n")
	Probe.arm(n, 0, 1)
	if not t.require(
			Probe.count(n, Probe.FRAG) == 1,
			"the invader carries a frag grenade",
	):
		return
	var brain := t.controller(&"n", &"current_act")
	if not t.require(await Flank.settle(t, brain), "the invader decides"):
		return
	var zone := _throw_zone(brain)
	if not t.require(
			not zone.is_empty() and n.global_position.distance_to(HOSTILE_AT) < Probe.FRAG_ZONE,
			"set-up: a frag option against the householder exists, the invader inside its zone",
	):
		return
	t.check(
		zone["tags"].get("no_safe_spot", false),
		"the option is tagged no_safe_spot (tags %s)" % str(zone["tags"]),
	)
	t.check(
		not GrenadeAi.offered(brain).has("grenade"),
		"GRENADE is not offered (offered %s)" % str(GrenadeAi.offered(brain)),
	)
	t.check(not t.happened(&"throw"), "and nothing was thrown")

	# Its legs back: the wall beside the doorway is within the fuse's reach.
	n.movement.speed = SPEED
	await Flank.settle(t, brain)
	zone = _throw_zone(brain)
	t.check(
		not zone.is_empty() and not zone["tags"].get("no_safe_spot", false),
		"free to walk the option is not tagged (tags %s)" % str(zone.get("tags")),
	)
	t.check(
		GrenadeAi.offered(brain).has("grenade"),
		"and GRENADE is offered (offered %s)" % str(GrenadeAi.offered(brain)),
	)


## The frag's option against the householder in the last snapshot, or {}.
func _throw_zone(brain: Node) -> Dictionary:
	for z: Dictionary in Spot.throws(brain):
		if z.get("kind", &"frag") == &"frag":
			return z
	return {}
