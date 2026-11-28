extends GameTest
## DR11 (D18, #194): at 0 HP a door comes off its hinges as a free 3D body driven by the
## blow and lies where physics lets it, here flat on the far side of the blow that felled it: four
## kicks from the pull side (a hollow door's 80 HP) throw it into the room the kicker faces; four
## rounds from the west throw it east. Lying flat it is walk-over (a puppet crosses it and the
## doorway), stops no round and no sight that passes above it, and is no longer usable. An ajar
## door felled by kicks from its pull side, which also push it toward shut, stays where it fell.

const JAMB := 20.0
const Probe := preload("res://tests/_objects/piece_probe.gd")
const KICKED := 250.0
const SHOT := 650.0
const WALKED_ROW := 450.0
const AJAR_ROW := 100.0
## The shove of a kick (the spec's number: `docs/doors.md` DR10).
const KICK_IMPULSE := 2200.0
const SIGHT_ROW := 850.0
## How far out from the wall line the fallen door's middle lies, at least, as a share of the leaf's
## height: a leaf toppling off its foot would land its middle half its height out; it tips with its
## foot slipping back, so a quarter says it fell clear of the doorway and not onto the threshold.
const BEYOND_SHARE := 0.25
## The highest a leaf lying flat reaches (px): its thickness and the body's resting gap.
const FLAT_TOP := 9.0
## The most (px) a leaf walked over may be moved by the walker.
const WALKED_OVER := 5.0


func describe() -> Dictionary:
	return {
		"name": "A door at 0 HP is thrown off its hinges and lies beyond the doorway",
		"description": "A hollow door kicked to 0 HP from its pull side lands west, a hollow door "
			+ "shot to 0 HP from the west lands east, each a free body that lies flat; the "
			+ "fallen door is walked over and stops no round and no sight.",
		"tags": ["door", "objects", "damage", "kick"],
		"timeout": 25.0,
	}


func _doorway(y: float, id: String, angle := 0.0) -> Dictionary:
	return {
		"pos": Vector2(400, y), "width": 52.0,
		"door": {
			"name": id, "material": "hollow", "style": "flush",
			"hinge": Vector2(400, y - JAMB), "swing_into": Vector2.RIGHT, "angle": angle,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 1000) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 1000) },
	], [
		_doorway(KICKED, "kicked"), _doorway(SHOT, "shot"),
		_doorway(WALKED_ROW, "walked"), _doorway(SIGHT_ROW, "seen"),
		_doorway(AJAR_ROW, "ajar_kicked", 60.0),
	])
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	s.von_down()
	s.actor(&"kicker", &"puppet", Vector2(430, KICKED))
	s.actor(&"shooter", &"puppet", Vector2(300, SHOT), { "start_slot": 3 })
	s.actor(&"walker", &"puppet", Vector2(300, WALKED_ROW))
	s.actor(&"watcher", &"invader", Vector2(330, SIGHT_ROW), {
		"movement:speed": 0.0, "facing": Vector2.RIGHT,
	})
	s.actor(&"hidden", &"puppet", Vector2(580, SIGHT_ROW), { "max_health": 100_000.0 })
	s.actor(&"target", &"puppet", Vector2(580, SHOT), { "max_health": 400.0 })


func run(t: TestContext) -> void:
	t.puppet(&"kicker").aim_at(Vector2(300, KICKED))
	t.puppet(&"shooter").aim_at(Vector2(400, SHOT))
	await t.seconds(0.6)
	# first, while it is quiet: the watcher turns toward gunfire and kicks
	await _sight_through(t)
	for _i in 4:
		t.puppet(&"kicker").kick()
		await t.seconds(0.55)
	for _i in 4:
		t.puppet(&"shooter").shoot()
		await t.seconds(0.4)
	await t.seconds(0.5)
	var kicked = t.object(&"kicked")
	var shot = t.object(&"shot")
	await Probe.settle(t, kicked, 10.0)
	await Probe.settle(t, shot, 10.0)
	await _stays_down(t)
	_lies_beyond(t, kicked, -1.0, "kicked from the east, it lies west")
	_lies_beyond(t, shot, 1.0, "shot from the west, it lies east")
	# the door on the shot row is down: a round goes through to the target behind it
	t.puppet(&"shooter").shoot()
	await t.seconds(1.0)
	var target := t.actor(&"target")
	t.check(
		target.health < target.max_health,
		"a round passes the fallen door (%.0f / %.0f)" % [target.health, target.max_health],
	)
	await _walk_over(t)


## The door lies down, flat on the floor `dir_x` (-1 west, +1 east) of its doorway: its middle at
## least a quarter of the leaf's height off the wall line, a free 3D body, with no 2D collider to
## walk into.
func _lies_beyond(t: TestContext, door: Node2D, dir_x: float, what: String) -> void:
	t.check(door.is_down(), "%s: it is down" % what)
	var out := BEYOND_SHARE * ObjectStructureMeshConfig.door_height
	t.check(
		(Probe.middle(door).x - 400.0) * dir_x >= out,
		"%s: its middle is %.0f px off the wall line" % [what, Probe.middle(door).x - 400.0],
	)
	t.check(Probe.body(door) is PieceBody, "%s: it is a free body" % what)
	t.check(
		Probe.lean(door) > 70.0 and Probe.top(door) <= FLAT_TOP,
		"%s: it lies flat (lean %.0f, top %.1f px)" % [what, Probe.lean(door), Probe.top(door)],
	)
	t.check(
		door.fallen_footprint().is_empty(),
		"%s: it has no obstacle footprint to walk into" % what,
	)


## A puppet crosses the doorway of a fallen door, over the door.
func _walk_over(t: TestContext) -> void:
	var walked = t.object(&"walked")
	var puppet := t.puppet(&"walker")
	t.check(not walked.is_down(), "the walked door still stands, to be knocked down")
	# felled with a blow past its HP through the hittable contract: the kicks and rounds above have
	# shown how a door falls, this row is the walk
	walked.take_damage(1000.0)
	t.check(walked.is_down(), "a blow past its HP knocks a door down")
	# the leaf lies where it fell before the walk starts, so the walk is over it, not a shove
	await Probe.settle(t, walked, 10.0)
	var lay := Probe.middle(walked)
	puppet.walk_to(Vector2(560, WALKED_ROW))
	t.check(
		await t.until(func(): return t.actor(&"walker").global_position.x > 500.0, 4.0),
		"a puppet walks over the fallen door and through the doorway (x %.0f)"
			% t.actor(&"walker").global_position.x,
	)
	var shoved := Probe.middle(walked).distance_to(lay)
	t.check(shoved < WALKED_OVER, "and walks over it, not shoving it (moved %.0f px)" % shoved)


## An NPC sees a puppet through a doorway whose door is down.
func _sight_through(t: TestContext) -> void:
	var seen = t.object(&"seen")
	var brain := t.controller(&"watcher", &"known_contacts_for_display")
	var sees := func() -> bool:
		for c in brain.known_contacts_for_display():
			if str(c["name"]) == "hidden" and c["visible"]:
				return true
		return false
	await t.seconds(0.5)
	t.check(not sees.call(), "an NPC does not see through the standing door")
	seen.take_damage(1000.0)
	t.check(
		await t.until(sees, 4.0),
		"and sees through the doorway once the door is down and has fallen",
	)


## An ajar door felled by a kick from its pull side (the strike shoves it toward shut, then deals
## its damage, as a boot does) lies where it fell: the shove that turned the leaf toward shut does
## not carry on and put the fallen leaf back on its hinge. Once at rest it stays put.
func _stays_down(t: TestContext) -> void:
	var door = t.object(&"ajar_kicked")
	door.apply_impulse(Vector2.LEFT * KICK_IMPULSE)
	door.take_blow(&"kick", 1000.0, Vector2.LEFT * KICK_IMPULSE, 30.0)
	await t.frames(2)
	t.check(door.is_down(), "a kick from the pull side fells the ajar door")
	t.check(await Probe.settle(t, door, 10.0), "and it comes to rest")
	var lies: Vector2 = door.global_position
	var turned: float = door.global_rotation
	await t.seconds(0.5)
	t.check(
		door.global_position.distance_to(lies) < 0.5
		and is_equal_approx(door.global_rotation, turned),
		"and it stays where it fell (moved %.1f px)" % door.global_position.distance_to(lies),
	)
