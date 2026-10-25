extends GameTest
## R3 (ticket #61): a weapon style is a look only; what a gun or grenade does is the same in every
## style. One shooter and one thrower, re-armed in each weapon style in turn
## (`Character.set_loadout(kit)`, the kit's `weapon_style`), do the very same thing from the very
## same spot:
## - each gun (pistol clicked every frame, SMG and rifle on a held trigger) fires as many rounds at
##   the same moments, its `shot` events name the same gun, power and muzzle, its rounds strike the
##   target for the same damage, and its `sound` events (kind `shot`) have the same profile, volume
##   and pitch as the `police` gun's;
## - each grenade (frag, stun) thrown at the same point tells the same `throw_stats()` (held, and
##   live in flight), comes to rest at the same spot, bursts the same time after it left the hand
##   with the same `explosion` (kind, radius, position), and its burst does the same to a dummy
##   standing beside it (a frag's blast damage, a stun's blind and deaf seconds) as the `police`
##   grenade's.
## Randomness is pinned so equal means equal: no spread (`GunConfig` copy), no sound jitter, a fixed
## bullet height, a still pose.

const StyleProbe := preload("res://tests/_items/weapon_style_probe.gd")
const SHOOTER_AT := Vector2(200, 150)
const TARGET_AT := Vector2(420, 150)
## How long each gun is fired in each style (s), and how long its last rounds have to land.
const WINDOW := 0.5
const LANDING := 0.5
## How long the shooter (or the thrower) stands after it is re-armed before it fires (or throws):
## long enough for the last burst's recoil (or throw) to have eased out of its hands, so every style
## fires and throws from the very same hold.
const SETTLE := 1.5
const THROWER_AT := Vector2(300, 600)
const THROW_TO := Vector2(740, 600)
## Where the thrower waits while its grenade bursts (out of every burst's reach), and where the
## dummies wait their turn.
const THROWER_PARK := Vector2(100, 950)
const DUMMY_PARK := Vector2(1450, 120)
const DUMMY_PARK_STEP := Vector2(0, 120)
## Where each grenade's dummy stands from the aim point: a frag's within the blast and short of the
## kill radius, a stun's inside the flash and the bang.
const DUMMY_OFFSET := { &"frag": Vector2(0, 160), &"stun": Vector2(0, 200) }
const NEAR_PX := 2.0
const NEAR_S := 0.02


func describe() -> Dictionary:
	return {
		"name": "A weapon style changes nothing a gun or grenade does",
		"description": "Every gun fires, strikes and sounds the same in police, scrap and pipe; "
			+ "every grenade's stats, rest point, fuse and burst are the same.",
		"tags": ["style", "item", "gun", "grenade", "sound", "fire rate"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1600, 1000))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.switch(&"physics.debris", false)
	s.switch(&"projectile.flyover", false)
	s.switch(&"audio.sound", true)
	s.set_static(SoundConfig, &"pitch_jitter", 0.0)
	s.set_static(SoundConfig, &"volume_jitter_db", 0.0)
	s.set_static(
		SoundConfig,
		&"category_range",
		{ &"shot": 1.0e9, &"impact": 1.0e9, &"footstep": 1.0e9, &"reload": 1.0e9 },
	)
	s.set_static(BallisticsFlightConfig, &"bullet_height", 50.0)
	s.set_static(CharacterConfig, &"pose_breath", 0.0)
	s.set_static(CharacterConfig, &"pose_glance", 0.0)
	var guns: Dictionary = GunConfig.guns.duplicate(true)
	for gun in guns:
		guns[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, &"guns", guns)
	s.actor(
		&"shooter",
		&"puppet",
		SHOOTER_AT,
		{ "facing": Vector2.RIGHT, "aim_point": TARGET_AT, "max_health": 100_000.0 },
	)
	s.actor(
		&"target",
		&"puppet",
		TARGET_AT,
		{ "facing": Vector2.LEFT, "aim_point": SHOOTER_AT, "max_health": 1.0e9 },
	)
	s.actor(
		&"thrower",
		&"puppet",
		THROWER_AT,
		{ "facing": Vector2.RIGHT, "aim_point": THROW_TO, "max_health": 100_000.0 },
	)
	var i := 0
	for kind: StringName in StyleProbe.GRENADES:
		for style in StyleProbe.STYLES:
			s.actor(
				_dummy(kind, style),
				&"puppet",
				DUMMY_PARK + DUMMY_PARK_STEP * i,
				{ "max_health": 1.0e9 },
			)
			i += 1


func run(t: TestContext) -> void:
	for gun: StringName in StyleProbe.GUNS:
		var fired := {}  # style -> what the gun did
		for style in StyleProbe.STYLES:
			fired[style] = await _fire(t, gun, style)
		for style in StyleProbe.STYLES:
			if style != StyleProbe.DEFAULT_STYLE:
				_compare_gun(t, gun, style, fired[style], fired[StyleProbe.DEFAULT_STYLE])
	for kind: StringName in StyleProbe.GRENADES:
		var thrown := {}  # style -> what the grenade did
		for style in StyleProbe.STYLES:
			thrown[style] = await _throw(t, kind, style)
			if thrown[style].is_empty():
				return
		for style in StyleProbe.STYLES:
			if style != StyleProbe.DEFAULT_STYLE:
				_compare_grenade(t, kind, style, thrown[style], thrown[StyleProbe.DEFAULT_STYLE])


## Arm the shooter with `gun` in `style`, stand the target back in place, fire for `WINDOW` and let
## the rounds land; returns what it did: `{ shots: [{ time, gun, power, position }] (time from the
## first), hits: [{ damage, outcome }], sounds: [{ profile, volume_db, pitch }] }`.
func _fire(t: TestContext, gun: StringName, style: StringName) -> Dictionary:
	var shooter := t.actor(&"shooter")
	var slot: int = StyleProbe.GUNS[gun]
	shooter.set_loadout(StyleProbe.kit(slot, style))
	_place(t, &"shooter", SHOOTER_AT, TARGET_AT)
	_place(t, &"target", TARGET_AT, SHOOTER_AT)
	await t.seconds(SETTLE)
	t.expect_eq(
		shooter.current_item().style,
		style,
		"the shooter holds the %s in %s (the premise)" % [gun, style],
	)
	var mark := t.events.size()
	await _pull_trigger(t, shooter.is_automatic())
	await t.seconds(LANDING)
	var shots := _shots_since(t, mark, shooter)
	var hits := _hits_since(t, mark, shooter)
	var sounds := _shot_sounds_since(t, mark)
	t.check(not shots.is_empty(), "the %s in %s fires" % [gun, style])
	t.check(not hits.is_empty(), "the %s in %s strikes the target" % [gun, style])
	t.check(not sounds.is_empty(), "the %s in %s sounds" % [gun, style])
	return { "shots": shots, "hits": hits, "sounds": sounds }


## Fire the shooter's gun for `WINDOW`: the trigger held when `automatic`, else clicked every frame.
func _pull_trigger(t: TestContext, automatic: bool) -> void:
	var puppet := t.puppet(&"shooter")
	if automatic:
		puppet.hold_fire(true)
		await t.seconds(WINDOW)
		puppet.hold_fire(false)
	else:
		for i in roundi(WINDOW * Engine.physics_ticks_per_second):
			puppet.shoot()
			await t.frames(1)


## The `shooter`'s `shot` events since event `mark`: `[{ time, gun, power, position }]`, the time
## from the first.
func _shots_since(t: TestContext, mark: int, shooter: Node) -> Array:
	var own := _since(t, mark, &"shot").filter(
		func(e: Dictionary) -> bool: return e["data"].get("attacker") == shooter,
	)
	if own.is_empty():
		return []
	var first: float = own[0]["time"]
	return own.map(
		func(e: Dictionary) -> Dictionary: return {
			"time": e["time"] - first,
			"gun": e["data"]["gun"],
			"power": e["data"]["power"],
			"position": e["data"]["position"],
		},
	)


## The `shooter`'s rounds that struck the target since event `mark`: `[{ damage, outcome }]`.
func _hits_since(t: TestContext, mark: int, shooter: Node) -> Array:
	var target := t.actor(&"target")
	return _since(t, mark, &"hit").filter(
		func(e: Dictionary) -> bool:
			return e["data"].get("attacker") == shooter and e["data"].get("victim") == target,
	).map(
		func(e: Dictionary) -> Dictionary:
			return { "damage": e["data"]["damage"], "outcome": e["data"].get("outcome") },
	)


## The `sound` events of kind `shot` since event `mark`: `[{ profile, volume_db, pitch }]`.
func _shot_sounds_since(t: TestContext, mark: int) -> Array:
	return _since(t, mark, &"sound").filter(
		func(e: Dictionary) -> bool: return e["data"].get("kind") == &"shot",
	).map(
		func(e: Dictionary) -> Dictionary: return {
			"profile": e["data"]["profile"],
			"volume_db": e["data"]["volume_db"],
			"pitch": e["data"]["pitch"],
		},
	)


## Check that the `gun` in `style` did what the police one did.
func _compare_gun(
	t: TestContext,
	gun: StringName,
	style: StringName,
	got: Dictionary,
	police: Dictionary,
) -> void:
	var what := "the %s in %s" % [gun, style]
	_compare_shots(t, what, got["shots"], police["shots"])
	_compare_hits(t, what, got["hits"], police["hits"])
	_compare_sounds(t, what, got["sounds"], police["sounds"])


## Check that `what`'s `shots` came as the police gun's did (`police`): as many, at its moments,
## naming the same gun, as strong, from the same muzzle.
func _compare_shots(t: TestContext, what: String, shots: Array, police: Array) -> void:
	if not t.expect_eq(
			shots.size(),
			police.size(),
			"%s fires as many rounds in %.1f s as in police" % [what, WINDOW],
	):
		return
	for i in shots.size():
		var a: Dictionary = shots[i]
		var b: Dictionary = police[i]
		t.expect_near(
			a["time"],
			b["time"],
			0.001,
			"%s fires round %d at the police gun's moment (its rate)" % [what, i],
		)
		t.expect_eq(a["gun"], b["gun"], "%s's shot %d names the same gun" % [what, i])
		t.expect_near(
			a["power"],
			b["power"],
			0.0001,
			"%s's shot %d has the same power" % [what, i],
		)
		t.check(
			a["position"].distance_to(b["position"]) <= NEAR_PX,
			"%s's shot %d leaves the same muzzle (%s vs %s)"
				% [what, i, a["position"], b["position"]],
		)


## Check that `what`'s `hits` struck the target as the police gun's did (`police`): as often, for
## the same damage, meeting it the same way.
func _compare_hits(t: TestContext, what: String, hits: Array, police: Array) -> void:
	if not t.expect_eq(
			hits.size(),
			police.size(),
			"%s strikes the target as often as in police" % what,
	):
		return
	for i in hits.size():
		t.expect_near(
			hits[i]["damage"],
			police[i]["damage"],
			0.0001,
			"%s's hit %d deals the same damage" % [what, i],
		)
		t.expect_eq(
			hits[i]["outcome"],
			police[i]["outcome"],
			"%s's hit %d meets the target the same way" % [what, i],
		)


## Check that `what`'s shot `sounds` are the police gun's (`police`): as many, with the same
## profile, volume and pitch.
func _compare_sounds(t: TestContext, what: String, sounds: Array, police: Array) -> void:
	if not t.expect_eq(
			sounds.size(),
			police.size(),
			"%s sounds as many shots as in police" % what,
	):
		return
	for i in sounds.size():
		var a: Dictionary = sounds[i]
		var b: Dictionary = police[i]
		t.expect_eq(
			a["profile"],
			b["profile"],
			"%s's shot sound %d has the same profile" % [what, i],
		)
		t.expect_near(
			a["volume_db"],
			b["volume_db"],
			0.0001,
			"%s's shot sound %d has the same volume" % [what, i],
		)
		t.expect_near(
			a["pitch"],
			b["pitch"],
			0.0001,
			"%s's shot sound %d has the same pitch" % [what, i],
		)


## Arm the thrower with one `kind` grenade in `style`, stand its dummy beside the aim point, throw
## it there and wait for the burst; returns what it did: `{ stats, live_stats, rest, fuse, boom: {
## kind, radius, position }, blast: [damage], stun: [{ blind, deaf }]
## }` ({} when it could not be thrown, after a failed `require`).
func _throw(t: TestContext, kind: StringName, style: StringName) -> Dictionary:
	var thrower := t.actor(&"thrower")
	var slot: int = StyleProbe.GRENADES[kind]
	var dummy_id := _dummy(kind, style)
	var dummy := t.actor(dummy_id)
	var park: Vector2 = dummy.global_position
	thrower.set_loadout(StyleProbe.kit(slot, style, { slot: 1 }))
	_place(t, &"thrower", THROWER_AT, THROW_TO)
	_place(t, dummy_id, THROW_TO + DUMMY_OFFSET[kind], THROW_TO)
	await t.seconds(SETTLE)
	var item: Item = thrower.current_item()
	t.expect_eq(item.style, style, "the thrower holds the %s in %s (the premise)" % [kind, style])
	var out := { "stats": item.throw_stats() }
	var mark := t.events.size()
	t.puppet(&"thrower").shoot()
	if not await _record_flight(t, mark, kind, style, out):
		return {}
	await t.seconds(0.3)
	_record_effects(t, mark, dummy, out)
	var effect: Array = out["blast"] if kind == &"frag" else out["stun"]
	t.check(
		not effect.is_empty(),
		"the %s in %s's burst reaches its dummy (the premise)" % [kind, style],
	)
	_place(t, dummy_id, park, park + Vector2.LEFT)
	# A body moved this frame is still where it was in the physics space until the next step: the
	# next dummy is stood here only after.
	await t.frames(2)
	return out


## Follow the `kind` grenade in `style` thrown at event `mark` from the hand to its burst, the
## thrower parked meanwhile, into `out`: `live_stats`, `rest`, `fuse` and `boom`. Whether it left
## the hand and burst (false after a failed `require`).
func _record_flight(
	t: TestContext,
	mark: int,
	kind: StringName,
	style: StringName,
	out: Dictionary,
) -> bool:
	if not t.require(
			await t.until(func() -> bool: return _since(t, mark, &"throw").size() > 0, 1.0),
			"the %s in %s leaves the hand" % [kind, style],
	):
		return false
	var throw_time: float = _since(t, mark, &"throw")[0]["time"]
	_place(t, &"thrower", THROWER_PARK, THROW_TO)
	var live := t.world.get_tree().get_nodes_in_group("live_grenades")
	out["live_stats"] = live[0].throw_stats() if not live.is_empty() else {}
	if not t.require(
			await t.until(func() -> bool: return _since(t, mark, &"explosion").size() > 0, 5.0),
			"the %s in %s bursts" % [kind, style],
	):
		return false
	var boom: Dictionary = _since(t, mark, &"explosion")[0]
	var rests := _since(t, mark, &"grenade").filter(
		func(e: Dictionary) -> bool: return e["data"].get("stage") == &"rest",
	)
	out["rest"] = rests[0]["data"]["position"] if not rests.is_empty() else Vector2.INF
	out["fuse"] = boom["time"] - throw_time
	out["boom"] = {
		"kind": boom["data"]["kind"],
		"radius": boom["data"]["radius"],
		"position": boom["data"]["position"],
	}
	return true


## What the burst since event `mark` did to `dummy`, into `out`: `blast` (each blast hit's damage)
## and `stun` (each stun's `{ blind, deaf }`).
func _record_effects(t: TestContext, mark: int, dummy: Node, out: Dictionary) -> void:
	var blasted := func(e: Dictionary) -> bool:
		return e["data"].get("victim") == dummy and e["data"].get("outcome") == &"blast"
	var damage := func(e: Dictionary) -> float: return e["data"]["damage"]
	out["blast"] = _since(t, mark, &"hit").filter(blasted).map(damage)
	var stunned := func(e: Dictionary) -> bool: return e["data"].get("character") == dummy
	var blind_deaf := func(e: Dictionary) -> Dictionary:
		return { "blind": e["data"]["blind"], "deaf": e["data"]["deaf"] }
	out["stun"] = _since(t, mark, &"stun").filter(stunned).map(blind_deaf)


## Check that the `kind` grenade in `style` did what the police one did.
func _compare_grenade(
	t: TestContext,
	kind: StringName,
	style: StringName,
	got: Dictionary,
	police: Dictionary,
) -> void:
	var what := "the %s in %s" % [kind, style]
	t.expect_eq(got["stats"], police["stats"], "%s tells the same throw_stats() held" % what)
	t.expect_eq(
		got["live_stats"],
		police["live_stats"],
		"%s tells the same throw_stats() in flight" % what,
	)
	t.check(
		got["rest"].distance_to(police["rest"]) <= NEAR_PX,
		"%s comes to rest where the police one does (%s vs %s): its range"
			% [what, got["rest"], police["rest"]],
	)
	t.expect_near(
		got["fuse"],
		police["fuse"],
		NEAR_S,
		"%s bursts as long after it leaves the hand (its fuse)" % what,
	)
	t.expect_eq(
		got["boom"]["kind"],
		police["boom"]["kind"],
		"%s's explosion is the same kind" % what,
	)
	t.expect_near(
		got["boom"]["radius"],
		police["boom"]["radius"],
		0.0001,
		"%s's explosion has the same radius" % what,
	)
	t.check(
		got["boom"]["position"].distance_to(police["boom"]["position"]) <= NEAR_PX,
		"%s bursts at the same spot" % what,
	)
	_compare_effects(t, what, got, police)


## Check that `what`'s burst did to its dummy what the police grenade's did (`police`): as many
## blast hits for the same damage, as many stuns blinding and deafening as long.
func _compare_effects(t: TestContext, what: String, got: Dictionary, police: Dictionary) -> void:
	if t.expect_eq(
			got["blast"].size(),
			police["blast"].size(),
			"%s's blast strikes its dummy as often" % what,
	):
		for i in got["blast"].size():
			t.expect_near(
				got["blast"][i],
				police["blast"][i],
				0.0001,
				"%s's blast %d deals the same damage" % [what, i],
			)
	if t.expect_eq(got["stun"].size(), police["stun"].size(), "%s stuns its dummy as often" % what):
		for i in got["stun"].size():
			t.expect_near(
				got["stun"][i]["blind"],
				police["stun"][i]["blind"],
				0.0001,
				"%s blinds its dummy as long" % what,
			)
			t.expect_near(
				got["stun"][i]["deaf"],
				police["stun"][i]["deaf"],
				0.0001,
				"%s deafens its dummy as long" % what,
			)


## The raw bus events (`{ topic, data, time }`) of `topic` since event `mark`.
func _since(t: TestContext, mark: int, topic: StringName) -> Array:
	return t.events.slice(mark).filter(func(e: Dictionary) -> bool: return e["topic"] == topic)


## Stand puppet `who` at `at`, still, aiming at `look`.
func _place(t: TestContext, who: StringName, at: Vector2, look: Vector2) -> void:
	var c := t.actor(who)
	c.global_position = at
	c.velocity = Vector2.ZERO
	t.puppet(who).aim_at(look)


func _dummy(kind: StringName, style: StringName) -> StringName:
	return StringName("dummy_%s_%s" % [kind, style])
