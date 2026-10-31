extends GameTest
## DR12: the doors are heard, every sound synthesized like the rest. A door posts one `&"door"`
## event at each stage of its life (`open`: a swing starting to open, `shut`: the latch as it
## closes, `burst`: the latch giving, `down`: the fall, `glass`: the panes shattering), with its
## `material`, and `Sound` plays one voice of that material's recipe (`leaf/<material>/<stage>`) at
## the door.
## A hollow door is used open and shut, burst by two kicks and felled by four; a steel door is used
## open and shut and burst by a frag; a glass-panel door's frame opens and its panes shatter on a
## round. A run of scroll notches on a door is one movement: one creak, not one per notch, and a
## notch after the door has rested creaks again. The profile names are the spec's
## (`docs/doors.md` DR12), kept here.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const SoundProbe := preload("res://tests/_audio/sound_probe.gd")
const JAMB := 20.0
## The rows (y of the doorway on the wall at x 400).
const USED := 100.0
const BURST := 250.0
const FALL := 400.0
const STEEL := 550.0
const PANES := 700.0
const GLASS_FRAME := 850.0
const SCROLLED := 1000.0
const SLOWLY_SCROLLED := 1150.0
const FRAG_DOOR := Vector2(1600, 200)
## How near the door a sound must be heard (px): the doorway's middle, a leaf away at most.
const AT_THE_DOOR := 30.0
## Seconds to let a swing finish (a full swing is 0.4 s), and the rest after which a door's next
## movement is a new one.
const SWING := 0.7
const RESTED := 1.5
## Seconds between the uses of a door opened, shut and opened at once (a swing takes 0.4).
const REVERSAL := 0.1
## Notches of a scroll slower than the creak gap lasts, and the seconds between them.
const SLOW_NOTCHES := 6
const SLOW_NOTCH_EVERY := 0.25
## The puppets that face their door, which lies to the east.
const FACING_EAST: Array[StringName] = [
	&"user", &"burster", &"steel_user", &"frame_user", &"scroller", &"slow_scroller",
]
const NOTCHES := 5
const NOTCH_DEGREES := 10.0
## A clang is what still rings on after the strike: per stage, the second from which the sound is
## judged (a fall's thud lands at 0.11 s), and a steel door's rings on more than this many times a
## wooden door's.
const RINGS := { &"shut": 0.12, &"burst": 0.12, &"down": 0.35 }
const MORE_RING := 3.0


func describe() -> Dictionary:
	return {
		"name": "Doors sound: creak, latch, burst, fall and shattering glass",
		"description": "A hollow door opens, shuts, bursts and falls, a steel door opens, shuts "
			+ "and bursts, a glass-panel door opens and its panes shatter: each posts one door "
			+ "event and plays one voice of its material's recipe at the door; a run of scroll "
			+ "notches creaks once.",
		"tags": ["sound", "door", "audio"],
		"timeout": 40.0,
	}


func _doorway(at: Vector2, material: String, style: String, id: String) -> Dictionary:
	return {
		"pos": at, "width": 52.0,
		"door": {
			"name": id, "material": material, "style": style,
			"hinge": at - Vector2(0, JAMB), "swing_into": Vector2.RIGHT,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 1300) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 1300) },
		{ "key": "west_b", "type": "living_room", "rect": Rect2(1200, 0, 400, 400) },
		{ "key": "east_b", "type": "bedroom", "rect": Rect2(1600, 0, 400, 400) },
	], [
		_doorway(Vector2(400, USED), "hollow", "flush", "used"),
		_doorway(Vector2(400, BURST), "hollow", "flush", "burst"),
		_doorway(Vector2(400, FALL), "hollow", "flush", "fall"),
		_doorway(Vector2(400, STEEL), "steel", "riveted", "steel"),
		_doorway(Vector2(400, PANES), "glass", "panes", "panes"),
		_doorway(Vector2(400, GLASS_FRAME), "glass", "panes", "frame"),
		_doorway(Vector2(400, SCROLLED), "hollow", "flush", "scrolled"),
		_doorway(Vector2(400, SLOWLY_SCROLLED), "hollow", "flush", "slowly_scrolled"),
		_doorway(FRAG_DOOR, "steel", "riveted", "blasted"),
	])
	s.switch(&"projectile.flyover", false)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	var heard: Dictionary = SoundProbe.EVERYWHERE.duplicate()
	heard[&"door"] = 1.0e9
	s.set_static(SoundConfig, &"category_range", heard)
	s.von_down()
	s.actor(&"user", &"puppet", Vector2(370, USED))
	s.actor(&"burster", &"puppet", Vector2(370, BURST))
	# on the side the leaf swings toward: a kick from there only damages the door, until it falls
	s.actor(&"feller", &"puppet", Vector2(431, FALL))
	s.actor(&"steel_user", &"puppet", Vector2(370, STEEL))
	s.actor(&"shooter", &"puppet", Vector2(300, PANES), { "start_slot": 3 })
	s.actor(&"frame_user", &"puppet", Vector2(370, GLASS_FRAME))
	s.actor(&"scroller", &"puppet", Vector2(370, SCROLLED))
	s.actor(&"slow_scroller", &"puppet", Vector2(370, SLOWLY_SCROLLED))
	s.actor(&"thrower", &"puppet", Vector2(1250, 200), { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	Probe.arm(t.actor(&"thrower"), 0, 1)
	for who: StringName in FACING_EAST:
		t.puppet(who).aim_at(t.actor(who).global_position + Vector2.RIGHT * 100.0)
	t.puppet(&"feller").aim_at(Vector2(300, FALL))
	t.puppet(&"shooter").aim_at(Vector2(400, PANES))
	await t.seconds(0.6)
	await _used(t, &"user", &"used", "hollow")
	await _reversed(t)
	await _used(t, &"steel_user", &"steel", "steel")
	await _burst_and_fall(t)
	await _glass(t)
	await _frag_on_steel(t)
	await _scrolled(t)
	await _scrolled_slowly(t)
	_recipes(t)


## A door used open: one `open` event and one voice; used again: one `shut`, as the leaf arrives.
func _used(t: TestContext, who: StringName, id: StringName, material: String) -> void:
	var door := t.object(id)
	t.puppet(who).use()
	await t.seconds(SWING)
	t.check(door.angle() > 89.0, "the %s door is opened" % id)
	_expect_once(t, door, &"open", material)
	t.check(_events(t, door, &"shut").is_empty(), "the %s door's latch is not heard yet" % id)
	t.puppet(who).use()
	await t.seconds(SWING)
	t.check(door.angle() < 1.0, "the %s door is shut again" % id)
	_expect_once(t, door, &"open", material)
	_expect_once(t, door, &"shut", material)
	for stage: StringName in [&"burst", &"down", &"glass"]:
		t.check(_events(t, door, stage).is_empty(), "using the %s door posts no %s" % [id, stage])


## A door opened, shut and opened again at once is three movements: it creaks each time it opens,
## the second not swallowed because the first was a moment ago.
func _reversed(t: TestContext) -> void:
	var door := t.object(&"used")
	var creaks := _events(t, door, &"open").size()
	t.puppet(&"user").use()
	await t.seconds(REVERSAL)
	t.puppet(&"user").use()
	await t.seconds(REVERSAL)
	t.puppet(&"user").use()
	await t.seconds(SWING)
	t.check(door.angle() > 89.0, "the door is open again")
	t.expect_eq(_events(t, door, &"open").size(), creaks + 2, "it creaks at each opening")
	t.expect_eq(_voices(t, door, "hollow", &"open").size(), creaks + 2, "and each is heard")
	t.puppet(&"user").use()
	await t.seconds(SWING)


## Two kicks from the push side burst a hollow door: one `burst` and no creak; four kicks from the
## pull side fell another: one `down`, and no burst.
func _burst_and_fall(t: TestContext) -> void:
	var burst := t.object(&"burst")
	for _i in 2:
		t.actor(&"burster").global_position = Vector2(370, BURST)
		t.puppet(&"burster").kick()
		await t.seconds(0.55)
	t.check(burst.angle() > 89.0, "two kicks burst the hollow door open")
	_expect_once(t, burst, &"burst", "hollow")
	t.check(_events(t, burst, &"open").is_empty(), "a burst is a bang, not a creak")
	var fall := t.object(&"fall")
	for _i in 4:
		t.puppet(&"feller").kick()
		await t.seconds(0.55)
	t.check(fall.is_down(), "four kicks from the pull side fell the hollow door")
	_expect_once(t, fall, &"down", "hollow")
	t.check(_events(t, fall, &"burst").is_empty(), "from the pull side nothing burst")


## A glass-panel door's frame creaks open; the first round on another shatters its panes, once.
func _glass(t: TestContext) -> void:
	var frame := t.object(&"frame")
	t.puppet(&"frame_user").use()
	await t.seconds(SWING)
	_expect_once(t, frame, &"open", "glass")
	var panes := t.object(&"panes")
	t.puppet(&"shooter").shoot()
	await t.seconds(0.5)
	t.check(panes.look.broken, "the round shatters the panes")
	_expect_once(t, panes, &"glass", "glass")
	t.puppet(&"shooter").shoot()
	await t.seconds(0.5)
	_expect_once(t, panes, &"glass", "glass")


## A frag's close blast bursts a steel door's latch: the steel burst.
func _frag_on_steel(t: TestContext) -> void:
	await Probe.throw_at(t, &"thrower", Probe.FRAG, FRAG_DOOR - Vector2(50, 0))
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag goes off"):
		return
	var blasted := t.object(&"blasted")
	t.check(
		await t.until(func(): return blasted.angle() > 89.0, 1.0),
		"the blast bursts the steel door open",
	)
	_expect_once(t, blasted, &"burst", "steel")


## Five notches in a row turn the door 50 degrees and creak once; after it has rested a notch more
## is a movement of its own and creaks again.
func _scrolled(t: TestContext) -> void:
	var door := t.object(&"scrolled")
	for _i in NOTCHES:
		t.puppet(&"scroller").turn_door(1.0)
		await t.frames(2)
	await t.seconds(SWING)
	t.expect_near(door.angle(), NOTCHES * NOTCH_DEGREES, 0.5, "the notches turn the door")
	_expect_once(t, door, &"open", "hollow")
	await t.seconds(RESTED)
	t.puppet(&"scroller").turn_door(1.0)
	await t.seconds(SWING)
	t.expect_eq(_events(t, door, &"open").size(), 2, "a notch after a rest is a new creak")
	t.expect_eq(_voices(t, door, "hollow", &"open").size(), 2, "and is heard")


## Notches a quarter second apart for longer than the creak gap are still one movement: one creak.
func _scrolled_slowly(t: TestContext) -> void:
	var door := t.object(&"slowly_scrolled")
	for _i in SLOW_NOTCHES:
		t.puppet(&"slow_scroller").turn_door(1.0)
		await t.seconds(SLOW_NOTCH_EVERY)
	await t.seconds(SWING)
	t.expect_near(door.angle(), SLOW_NOTCHES * NOTCH_DEGREES, 0.5, "the notches turn the door")
	_expect_once(t, door, &"open", "hollow")


## The recipes are the materials': a steel door's latch, burst and fall clang, ringing on long after
## a wooden door's thud has died away, and its groan is lower than a wooden door's creak; the glass
## is a bright shattering, not a thud.
func _recipes(t: TestContext) -> void:
	for variant in 2:
		for stage: StringName in RINGS:
			var from: float = RINGS[stage]
			var steel := _ringing(StringName("leaf/steel/%s" % stage), variant, from)
			var wood := _ringing(StringName("leaf/hollow/%s" % stage), variant, from)
			t.check(
				steel > wood * MORE_RING,
				"the steel door's %s rings on (%.2f of it past %.2f s) over the wooden door's %.2f"
					% [stage, steel, from, wood],
			)
		var groan := SoundProbe.brightness(SoundProbe.samples(&"leaf/steel/open", variant))
		var creak := SoundProbe.brightness(SoundProbe.samples(&"leaf/hollow/open", variant))
		t.check(
			groan < creak,
			"a steel door groans lower than a hollow one creaks (%.4f against %.4f)" % [
				groan,
				creak,
			],
		)
		var shatter := SoundProbe.samples(&"leaf/glass/glass", variant)
		t.check(
			SoundProbe.low_share(shatter) < 0.3,
			"shattering glass is bright, not a thud (%.2f of it under 250 Hz)"
				% SoundProbe.low_share(shatter),
		)


## The share of `profile`'s variant `variant` (its energy) that is still sounding `seconds` in.
func _ringing(profile: StringName, variant: int, seconds: float) -> float:
	var s := SoundProbe.samples(profile, variant)
	var from := int(seconds * SoundLibraryConfig.sample_rate)
	var total := 0.0
	var tail := 0.0
	for i in s.size():
		total += s[i] * s[i]
		if i >= from:
			tail += s[i] * s[i]
	return tail / maxf(total, 0.000001)


## The `door` events of `door` at `stage`.
func _events(t: TestContext, door: Node, stage: StringName) -> Array:
	return t.events_of(
		&"door",
		func(d: Dictionary) -> bool: return d["door"] == door and d["stage"] == stage,
	)


## The `sound` events of a `leaf/<material>/<stage>` profile near `door`.
func _voices(t: TestContext, door: Node2D, material: String, stage: StringName) -> Array:
	var doorway: Vector2 = door.hinge + (door.leaf_pose(0.0).x * door.width * 0.5)
	return SoundProbe.sounds(t, &"", "leaf/%s/%s" % [material, stage]).filter(
		func(d: Dictionary) -> bool:
			return (d["position"] as Vector2).distance_to(doorway) < AT_THE_DOOR
	)


## `door` posted exactly one `stage` event, of `material`, at its doorway, and exactly one voice of
## `leaf/<material>/<stage>` played there, at the event's own position.
func _expect_once(t: TestContext, door: Node2D, stage: StringName, material: String) -> void:
	var events := _events(t, door, stage)
	var what := "%s door's %s" % [door.name, stage]
	t.expect_eq(events.size(), 1, "the %s is posted once" % what)
	if events.is_empty():
		return
	t.expect_eq(String(events[0]["material"]), material, "the %s names its material" % what)
	var voices := _voices(t, door, material, stage)
	t.expect_eq(voices.size(), 1, "the %s plays one %s voice at the door" % [what, material])
	if not voices.is_empty():
		t.check(
			(voices[0]["position"] as Vector2).is_equal_approx(events[0]["position"]),
			"the %s is heard where the door posted it" % what,
		)
