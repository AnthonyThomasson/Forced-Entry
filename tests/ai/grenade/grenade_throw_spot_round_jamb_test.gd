extends GameTest
## G17, the lob judged as the grenade flies: a lob that clears the jamb by a ray from the thrower's
## centre but not from its throwing hand is not a clear lob, so GRENADE is offered through a throw
## spot, not in place, and the grenade really goes in. The Terrace house, bare; an invader with a
## stun outside the back door, off its axis to the north-east, sees a household puppet in the
## kitchen through it. From where it stands the line from its centre to the puppet clears the north
## jamb, the lob from its hand (where the Character says a grenade leaves it,
## `throw_release_offset`: 6 px behind it, 15 px to its right; 8 px either side) does not; thrown
## from there, a stun strikes the jamb more often than not. Scripted Von (COMBAT > GRENADE > stun
## when offered): its first COMBAT decision, made where it stands, offers GRENADE through a throw
## spot a short walk away with a clear lob from the hand; the throw leaves from that spot and the
## stun bursts in the kitchen on the puppet.
##
## Premises: the puppet cannot be killed and never shoots; the invader is armed at the start of
## `run`, the way Main arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const Spot := preload("res://tests/_ai/throw_spot_probe.gd")
const I_AT := Vector2(960, 190)
const H_AT := Vector2(660, 120)


func describe() -> Dictionary:
	return {
		"name": "A lob that only clears the jamb from the thrower's centre is thrown from a throw "
			+ "spot",
		"description": "An invader whose centre line to a householder clears the back door's jamb "
			+ "but whose hand's lob does not is offered GRENADE through a throw spot, not in "
			+ "place, throws from it, and the stun bursts in the kitchen.",
		"tags": ["ai", "grenade", "combat", "throw_spot", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([
		{ "pick": "combat" },
		{ "pick": "grenade" },
		{ "pick": "stun" },
		{ "pick": "engage" },
		{ "pick": "advance" },
		{ "pick": "retreat" },
	])
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"i", &"invader", I_AT, { "facing": (H_AT - I_AT).normalized() })
	GrenadeAi.hostile(s, &"h", H_AT, Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 1, 0)
	if not _set_up(t, inv):
		return
	var brain := t.controller(&"i", &"debug_zones")
	var seen := await Spot.watch_first_combat(t, brain, inv)
	var first: Dictionary = seen["first"]
	if not t.require(
			not first.is_empty() and (first["pos"] as Vector2).distance_to(I_AT) <= 12.0,
			"the invader made a COMBAT decision where it stands (walks %s)"
				% str(Spot.describe(seen["walks"])),
	):
		return
	t.check(
		first["combat"].has("grenade"),
		"GRENADE was offered (offered %s)" % str(first["combat"]),
	)
	var from := _check_throw_spot(t, inv, seen["zones"])
	if from == Vector2.INF:
		return
	await _check_thrown_from(t, inv, from)


func _set_up(t: TestContext, inv: Node) -> bool:
	if not t.require(
			Probe.count(inv, Probe.STUN) == 1,
			"the invader carries a stun (item_count(7) = %d)" % Probe.count(inv, Probe.STUN),
	):
		return false
	return t.require(
		GrenadeAi.line_clear(t, I_AT, H_AT)
			and Spot.lob_clear(t, I_AT, H_AT)
			and not Spot.hand_lob_clear(t, inv, I_AT, H_AT)
			and I_AT.distance_to(H_AT) <= Probe.MAX_RANGE,
		"set-up: in sight and in range, the centre line clears the jamb, the lob from the hand "
			+ "does not",
	)


# The throw spot the weighed throw names, checked; `Vector2.INF` when it names none.
func _check_throw_spot(t: TestContext, inv: Node, zones: Array) -> Vector2:
	var near := zones.filter(func(z): return (
		(z["point"] as Vector2).distance_to(H_AT) < 60.0 and Spot.from_of(z) != Vector2.INF
	))
	if not t.check(
			not near.is_empty(),
			"the throw it weighed names where it throws from (zones %s)" % str(zones),
	):
		return Vector2.INF
	var from := Spot.from_of(near[0])
	var point: Vector2 = near[0]["point"]
	t.check(
		from.distance_to(I_AT) >= 40.0,
		"a throw spot, not where it stands (%s)" % str(from.round()),
	)
	t.check(
		Spot.hand_lob_clear(t, inv, from, point) and from.distance_to(point) <= Spot.THROW_RANGE,
		"with a clear lob from the hand there, in range (%.0f px)" % from.distance_to(point),
	)
	var way := Spot.walk(t, I_AT, from)
	t.check(
		way["reaches"] and float(way["len"]) <= Spot.SHORT_WALK,
		"a short walk away (%.0f px, reaches %s)" % [way["len"], str(way["reaches"])],
	)
	return from


func _check_thrown_from(t: TestContext, inv: Node, from: Vector2) -> void:
	var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == inv)
	if t.check(not throws.is_empty(), "the invader threw (acts %s)" % GrenadeAi.acts(t, &"i")):
		var at: Vector2 = throws[0]["data"]["position"]
		t.check(
			at.distance_to(from) <= 30.0,
			"from the throw spot (thrown at %s, the spot %s)"
				% [str(at.round()), str(from.round())],
		)
		if t.check(await Probe.wait_boom(t, &"stun", 4.0), "the stun went off"):
			var boom: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
			t.check(
				Maps.HOUSE_KITCHEN.has_point(boom) and boom.distance_to(H_AT) < 110.0,
				"in the kitchen on the householder's spot (%s)" % str(boom.round()),
			)
