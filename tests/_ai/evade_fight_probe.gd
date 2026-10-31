extends RefCounted
## Shared helper for the grenade tests of an NPC that fights while it evades (G16; not a test
## itself): `const EvadeFight := preload("res://tests/_ai/evade_fight_probe.gd")`. `check` arms the
## world's defender `d` and puppet `thrower`, throws the grenade, waits for the defender to hold its
## evade spot and checks it shoots before the burst; `evade_fights_from_spot` (a frag) and
## `evade_stun_fights_from_spot` (a stun) hold a second invader in view of that spot,
## `evade_frag_cornered_fights` the thrower in view of a defender with no spot.

const Probe := preload("res://tests/_ai/grenade_probe.gd")


## Arm the defender `d` with a pistol and the puppet `thrower` with one grenade in `slot`, throw it
## at `aim`, then check that the defender, holding its evade spot (within `at_spot` px; with
## `no_spot`, evading with none it can reach in time), shoots before the burst.
static func check(
		t: TestContext,
		slot: int,
		aim: Vector2,
		at_spot: float,
		no_spot := false,
) -> void:
	var kind := &"frag" if slot == Probe.FRAG else &"stun"
	if not _armed(t, slot, kind):
		return
	await Probe.throw_at(t, &"thrower", slot, aim)
	if not t.require(
			await t.until(func(): return _evading(t), 2.0),
			"the defender takes up an evade from the %s" % kind,
	):
		return
	var held := func(): return _holding(t, at_spot, no_spot) or not Probe.booms(t, kind).is_empty()
	if not t.require(
			await t.until(held, 4.0) and Probe.booms(t, kind).is_empty(),
			"set-up: the defender holds its spot (%s, at %s) before the burst"
				% [str(_escape(t)), str(t.actor(&"d").global_position)],
	):
		return
	var held_at := t.time
	var fired := func(): return not _shots(t, held_at).is_empty() or not _evading(t)
	await t.until(fired, 4.0)
	var shots := _shots(t, held_at)
	var burst := Probe.booms(t, kind)
	var burst_at: float = INF if burst.is_empty() else float(burst[0]["time"])
	t.check(
		not shots.is_empty() and float(shots[0]["time"]) < burst_at,
		"holding (at its spot, or with none), the defender shot at the invader in view before the "
			+ "burst (%d shots from %.2f s; burst at %.2f s)" % [shots.size(), held_at, burst_at],
	)


## Arms both and checks the premise that the thrower carries the grenade.
static func _armed(t: TestContext, slot: int, kind: StringName) -> bool:
	Probe.arm(t.actor(&"d"))
	Probe.arm(t.actor(&"thrower"), int(slot == Probe.STUN), int(slot == Probe.FRAG))
	return t.require(
		Probe.count(t.actor(&"thrower"), slot) == 1,
		"the thrower carries a %s grenade (Character.inventory.item_count(%d))" % [kind, slot],
	)


## The defender's evade spot (`Vector2.INF`: none).
static func _escape(t: TestContext) -> Vector2:
	return t.controller(&"d", &"debug_grenades").debug_grenades()["escape"]


## Whether the defender is carrying out an evade plan.
static func _evading(t: TestContext) -> bool:
	return not t.controller(&"d", &"debug_state").debug_state().get("evade", {}).is_empty()


## Whether the defender evades and holds: at its spot, or (`no_spot`) with no spot to reach.
static func _holding(t: TestContext, at_spot: float, no_spot: bool) -> bool:
	var spot := _escape(t)
	if no_spot:
		return _evading(t) and spot == Vector2.INF
	return (_evading(t)
			and spot != Vector2.INF
			and t.actor(&"d").global_position.distance_to(spot) <= at_spot)


## The defender's rounds fired (raw `shot` events) at or after `since`.
static func _shots(t: TestContext, since: float) -> Array:
	var d := t.actor(&"d")
	return Probe.raw(t, &"shot", func(s): return s.get("attacker") == d).filter(
		func(e): return float(e["time"]) >= since
	)
