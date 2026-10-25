extends GameTest
## S6 (ticket #56) with G15: an NPC that goes blind rolls once against its `blind_fire_chance`; on a
## miss it holds its fire until it can see. This defender's chance is 0. It is fighting a hostile it
## can see when the flash hits it; the hostile then walks across its front. While blind it fires no
## round, it does not spot the hostile, and what it knows of it stays where it was last seen; when
## the blindness lifts it re-reads the hostile where it stands. (The chance 1 case, blind fire
## one-handed, is `stunned_defender_blind`.)
##
## Premises as `stunned_defender_blind`: the flash is `take_stun(6, 6)` called on the defender, as a
## grenade's flash would; the hostile is an invader *puppet* that cannot be killed and never shoots.
## Real Von; everything else is on.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const DEFENDER_AT := Vector2(200, 420)
## where the hostile is seen last
const FIRST_SPOT := Vector2(600, 420)
## 45 degrees off the first, well inside the defender's view cone, where it walks to
const SECOND_SPOT := Vector2(450, 170)
const BLIND := 6.0


func describe() -> Dictionary:
	return {
		"name": "A blinded defender that rolls no blind fire holds its fire until it can see",
		"description": "Blinded for 6 s, a defender with blind_fire_chance 0 fighting an invader "
			+ "fires no round while blind, keeps the invader's last-known spot while it walks "
			+ "across its front, and re-reads it once it can see.",
		"tags": ["ai", "grenade", "stun", "blind", "von"],
		"requires_von": true,
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 500))
	s.actor(&"d", &"defender", DEFENDER_AT, { "facing": Vector2.RIGHT })
	s.set_props(&"d", "GoalController", { "blind_fire_chance": 0.0 })
	s.actor(
		&"p",
		&"puppet",
		FIRST_SPOT,
		{ "faction": &"invader", "max_health": 1_000_000.0, "aim_point": DEFENDER_AT },
	)


## The defender's remembered position of the invader, from its contacts: `{ pos, visible }`, or {}
## when it knows none.
func _known(brain: Node, p: Node) -> Dictionary:
	for c in brain.known_contacts_for_display():
		if c.get("node") == p:
			return c
	return {}


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var p := t.actor(&"p")
	var brain := t.controller(&"d", &"current_act")
	t.check(
		"blind_fire_chance" in brain and is_zero_approx(float(brain.get("blind_fire_chance"))),
		"the defender's GoalController has blind_fire_chance, set to 0 (%s)"
			% str(brain.get("blind_fire_chance")),
	)
	var fighting := func(): return (
		not _known(brain, p).is_empty() and str(brain.current_act()).begins_with("combat")
	)
	if not t.require(
			await t.until(fighting, 20.0),
			"the defender knows the invader and is fighting it (acting: %s)"
				% str(brain.current_act()),
	):
		return
	var seen_at: Vector2 = _known(brain, p).get("pos", FIRST_SPOT)

	var shots := { "seen": _in_flight(t, d), "blind_rounds": 0 }  # rounds fired while blind
	if not t.require(Probe.stun(d, BLIND, BLIND), "Character.take_stun(blind, deaf) exists"):
		return
	var flashed := t.time
	t.puppet(&"p").walk_to(SECOND_SPOT)
	await t.frames(1)
	t.check(Probe.blind(d), "the flash blinded the defender (stun.is_blind)")
	while t.time < flashed + 3.5:
		_capture(t, d, shots)
		await t.frames(1)
	_check_held_at_old_spot(t, brain, p, seen_at)

	while Probe.blind(d) and t.time < flashed + BLIND + 2.0:
		_capture(t, d, shots)
		await t.frames(1)
	t.check(t.time - flashed >= BLIND - 0.5, "(the blindness ran its course)")
	t.check(
		shots["blind_rounds"] == 0,
		"it held its fire while blind (%d rounds fired blind)" % shots["blind_rounds"],
	)
	await _check_sees_again(t, brain, p)


## The defender's rounds already in flight, which left the barrel before the flash: not blind
## ones. `{ instance id: true }`.
func _in_flight(t: TestContext, d: Node) -> Dictionary:
	var seen := {}
	for n in t.world.get_children():
		if String(n.name).begins_with("Projectile") and n is Node2D and n.get("ignore") == d:
			seen[n.get_instance_id()] = true
	return seen


## Counts each round the defender fired blind that has appeared since the last frame.
func _capture(t: TestContext, d: Node, shots: Dictionary) -> void:
	var seen: Dictionary = shots["seen"]
	for n in t.world.get_children():
		if (String(n.name).begins_with("Projectile")
				and n is Node2D
				and not seen.has(n.get_instance_id())
				and n.get("ignore") == d):
			seen[n.get_instance_id()] = true
			if Probe.blind(d):
				shots["blind_rounds"] += 1


## The invader walked across the defender's front, and the defender still holds it at the spot it
## last saw it, unseen.
func _check_held_at_old_spot(t: TestContext, brain: Node, p: Node, seen_at: Vector2) -> void:
	t.check(t.puppet(&"p").has_arrived(), "the invader walked across the defender's front")
	var known := _known(brain, p)
	t.check(
		not known.is_empty() and (known["pos"] as Vector2).distance_to(seen_at) < 60.0,
		"the defender still holds the invader at the spot it last saw it (%s, now at %s)"
			% [str(known.get("pos")), str(p.global_position.round())],
	)
	t.check(not known.is_empty() and not bool(known.get("visible", true)), "and does not see it")


## The blindness is over: it sees the invader again, where it is now.
func _check_sees_again(t: TestContext, brain: Node, p: Node) -> void:
	t.check(
		await t.until(
			func(): return (
				bool(_known(brain, p).get("visible", false))
					and (_known(brain, p)["pos"] as Vector2).distance_to(p.global_position) < 40.0
			),
			4.0,
		),
		"once it can see it re-reads the invader where it stands (acting: %s)"
			% str(brain.current_act()),
	)
