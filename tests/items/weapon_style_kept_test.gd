extends GameTest
## R3 (ticket #61): a dropped gun and a thrown grenade keep the weapon style they were held in.
## - Three gunmen armed in `scrap` (pistol, SMG, rifle; `Character.inventory.set_loadout(kit)`, the
##   kit's `weapon_style`) die; the `DroppedItem` each one's gun leaves shows scrap while it
##   skids and once at rest: the mesh and art its item shows (what the 3D render takes from
##   `dropped_mesh` / `dropped_texture`) are ones the scrap gun shows lying either side up, and none
##   is one the police or pipe gun shows so.
## - A thrower armed with a `pipe` frag throws it; the `ThrownGrenade` shows pipe in flight (above
##   12 px) and at rest: all of it is what the pipe frag shows lying, none what the police or scrap
##   frag shows.
## The reference looks are those of fresh items; every look is read off the `DroppedItem`'s /
## `ThrownGrenade`'s `item` (`tests/_items/weapon_style_probe.gd`).

const StyleProbe := preload("res://tests/_items/weapon_style_probe.gd")
## The gunmen, by gun: where each stands.
const GUNMEN := {
	&"pistol": Vector2(560, 120),
	&"smg": Vector2(700, 120),
	&"rifle": Vector2(840, 120),
}
const KEPT_GUN_STYLE := &"scrap"
const THROWER_AT := Vector2(150, 460)
const THROW_TO := Vector2(550, 460)
const KEPT_GRENADE_STYLE := &"pipe"
## How high (px) a thrown grenade is aloft.
const ALOFT := 12.0
## Frames between samples of a moving drawing.
const SAMPLE_FRAMES := 3
## Frames a lob may stay aloft before the test stops watching it fly (a throw to `THROW_TO` lands in
## well under a second).
const MAX_FLIGHT_FRAMES := 180


func describe() -> Dictionary:
	return {
		"name": "A dropped gun and a thrown grenade keep their weapon style",
		"description": "A gunman armed in scrap dies: the dropped gun shows scrap while it skids "
			+ "and at rest. A pipe frag thrown shows pipe in flight and at rest.",
		"tags": ["style", "item", "gun", "grenade", "drop", "art"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	for gun: StringName in GUNMEN:
		s.actor(
			gun,
			&"puppet",
			GUNMEN[gun],
			{ "facing": Vector2.DOWN, "movement:aim_point": GUNMEN[gun] + Vector2(0, 300) },
		)
	s.actor(
		&"thrower",
		&"puppet",
		THROWER_AT,
		{ "facing": Vector2.RIGHT, "movement:aim_point": THROW_TO, "max_health": 100_000.0 },
	)


func run(t: TestContext) -> void:
	var refs := _references(t)
	if refs.is_empty():
		return
	_arm(t)
	await t.seconds(0.5)
	var dropped := await _drop_guns(t)
	if dropped.is_empty():
		return
	await _check_dropped(t, dropped, refs)
	await _check_thrown(t, refs)


## What each gun and the frag shows lying in every style, either side up: kind -> style -> its set;
## {} after a failed `require` (a reference shows nothing).
func _references(t: TestContext) -> Dictionary:
	var refs := {}
	var slots := {}
	for gun: StringName in GUNMEN:
		slots[gun] = StyleProbe.GUNS[gun]
	slots[&"frag"] = StyleProbe.GRENADES[&"frag"]
	for kind: StringName in slots:
		refs[kind] = {}
		for style in StyleProbe.STYLES:
			refs[kind][style] = StyleProbe.lying_either_side(slots[kind], style)
			if not t.require(
					not refs[kind][style].is_empty(),
					"the %s %s shows something lying (the reference)" % [style, kind],
			):
				return {}
	return refs


## Arm each gunman with its gun in scrap and the thrower with one pipe frag.
func _arm(t: TestContext) -> void:
	for gun: StringName in GUNMEN:
		var slot: int = StyleProbe.GUNS[gun]
		t.actor(gun).inventory.set_loadout(StyleProbe.kit(slot, KEPT_GUN_STYLE))
	var frag_slot: int = StyleProbe.GRENADES[&"frag"]
	t.actor(&"thrower").inventory.set_loadout(
		StyleProbe.kit(frag_slot, KEPT_GRENADE_STYLE, { frag_slot: 1 }),
	)


## The gunmen die holding their scrap guns; returns gun -> the `DroppedItem` its gun left ({} after
## a failed `require`).
func _drop_guns(t: TestContext) -> Dictionary:
	var held := {}  # gun -> the item its gunman holds
	for gun: StringName in GUNMEN:
		var c := t.actor(gun)
		held[gun] = c.inventory.current_item()
		t.expect_eq(
			held[gun].art.style,
			KEPT_GUN_STYLE,
			"the %s's gunman holds it in scrap (the premise)" % gun,
		)
		c.take_damage(100_000.0)
	var dropped := {}  # gun -> its DroppedItem
	var found := await t.until(func() -> bool: return _collect_dropped(t, held, dropped), 2.0)
	if not t.require(
			found,
			"each dead gunman's gun lies in the world as a DroppedItem (found %s)"
				% [dropped.keys()],
	):
		return {}
	return dropped


## Gather into `dropped` (gun -> its `DroppedItem`) each `held` gun now lying in the world; whether
## every gunman's is.
func _collect_dropped(t: TestContext, held: Dictionary, dropped: Dictionary) -> bool:
	for n in t.world.get_children():
		if n is DroppedItem:
			for gun: StringName in held:
				if n.item == held[gun]:
					dropped[gun] = n
	return dropped.size() == GUNMEN.size()


## Check each `dropped` gun shows scrap while it skids and once at rest, against `refs`.
func _check_dropped(t: TestContext, dropped: Dictionary, refs: Dictionary) -> void:
	var skidding := {}  # gun -> what it drew while it moved
	for i in 6:
		await t.frames(SAMPLE_FRAMES)
		for gun: StringName in dropped:
			skidding[gun] = skidding.get(gun, {}).merged(_shown(dropped[gun]))
	await t.seconds(1.5)
	for gun: StringName in dropped:
		var item: Item = dropped[gun].item
		t.expect_eq(
			item.art.style,
			KEPT_GUN_STYLE,
			"the dropped %s keeps the style scrap (ItemArt.style)" % gun,
		)
		_check_drawn(t, skidding[gun], refs[gun], KEPT_GUN_STYLE, "the dropped %s, skidding," % gun)
		_check_drawn(
			t,
			_shown(dropped[gun]),
			refs[gun],
			KEPT_GUN_STYLE,
			"the dropped %s, at rest," % gun,
		)


## The thrower throws its pipe frag: check it shows pipe in flight and at rest, against
## `refs`.
func _check_thrown(t: TestContext, refs: Dictionary) -> void:
	var thrower := t.actor(&"thrower")
	t.expect_eq(
		thrower.inventory.current_item().art.style,
		KEPT_GRENADE_STYLE,
		"the thrower holds its frag in pipe (the premise)",
	)
	t.puppet(&"thrower").aim_at(THROW_TO)
	await t.seconds(0.4)
	t.puppet(&"thrower").shoot()
	if not t.require(
			await t.until(func() -> bool: return not _live(t).is_empty(), 1.5),
			"the frag leaves the hand as a ThrownGrenade",
	):
		return
	var grenade: ThrownGrenade = _live(t)[0]
	var aloft := await _shown_aloft(t, grenade)
	if not t.require(
			await t.until(
				func() -> bool: return t.happened(
					&"grenade",
					func(d: Dictionary) -> bool: return d.get("stage") == &"rest",
				),
				2.5,
			),
			"the frag comes to rest",
	):
		return
	if not t.require(is_instance_valid(grenade), "the frag has not burst yet at rest"):
		return
	await t.frames(2)
	var lying := _shown(grenade)
	t.expect_eq(
		grenade.item.art.style,
		KEPT_GRENADE_STYLE,
		"the thrown frag keeps the style pipe (ItemArt.style)",
	)
	_check_drawn(t, aloft, refs[&"frag"], KEPT_GRENADE_STYLE, "the thrown frag, in flight,")
	_check_drawn(t, lying, refs[&"frag"], KEPT_GRENADE_STYLE, "the thrown frag, at rest,")


## What `grenade` showed while aloft (above `ALOFT` px), watched each frame until it lies, bursts or
## `MAX_FLIGHT_FRAMES` pass.
func _shown_aloft(t: TestContext, grenade: ThrownGrenade) -> Dictionary:
	var aloft := {}
	var frames := 0
	while (is_instance_valid(grenade)
			and (frames < 3 or grenade.altitude() > 0.0)
			and frames < MAX_FLIGHT_FRAMES):
		await t.frames(1)
		frames += 1
		if is_instance_valid(grenade) and grenade.altitude() > ALOFT:
			aloft.merge(_shown(grenade))
	return aloft


## What a `DroppedItem` or a `ThrownGrenade` shows now: its item's lying mesh and art, on the side
## it lies on (a grenade has one).
func _shown(node: Node2D) -> Dictionary:
	var flip: bool = node.flipped() if node is DroppedItem else false
	return StyleProbe.lying(node.item, flip)


## Check that `drawn` (what a dropped or thrown item shows) is in `style`: not empty, every id one
## the `style` item shows lying (`refs[style]`), none one another style's shows.
func _check_drawn(
	t: TestContext,
	drawn: Dictionary,
	refs: Dictionary,
	style: StringName,
	what: String,
) -> void:
	if not t.check(not drawn.is_empty(), "%s shows something" % what):
		return
	t.check(
		StyleProbe.within(drawn, refs[style]),
		"%s shows only what the %s one shows lying" % [what, style],
	)
	for other in StyleProbe.STYLES:
		if other != style:
			t.check(
				StyleProbe.apart(drawn, refs[other]),
				"%s shows nothing the %s one shows lying" % [what, other],
			)


## The live grenades (the group `live_grenades`).
func _live(t: TestContext) -> Array:
	return t.world.get_tree().get_nodes_in_group("live_grenades")
