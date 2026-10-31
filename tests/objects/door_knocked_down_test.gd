extends GameTest
## DR11: at 0 HP a door comes off its hinges and lies flat beyond the doorway, on the far side of
## the blow that felled it: four kicks from the pull side (a hollow door's 80 HP) push it into the
## room the kicker faces; four rounds from the west push it east. It is then walk-over (a puppet
## crosses it and the doorway), casts no shadow, stops no round and no sight, and is no longer
## usable. An ajar door felled by kicks from its pull side, which also push it toward shut, stays
## where it fell.

const JAMB := 20.0
const KICKED := 250.0
const SHOT := 650.0
const WALKED_ROW := 450.0
const AJAR_ROW := 100.0
## The shove of a kick (the spec's number: `docs/doors.md` DR10).
const KICK_IMPULSE := 2200.0
const SIGHT_ROW := 850.0
## How far the fallen door lies out from the wall line, at least (its middle).
const BEYOND := 40.0


func describe() -> Dictionary:
	return {
		"name": "A door at 0 HP lies flat beyond the doorway",
		"description": "A hollow door kicked to 0 HP from its pull side falls west, a hollow door "
			+ "shot to 0 HP from the west falls east; the fallen door is walked over, casts no "
			+ "shadow and stops no round and no sight.",
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
	s.switch(&"projectile.flyover", false)
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
	s.actor(&"hidden", &"puppet", Vector2(480, SIGHT_ROW), { "max_health": 100_000.0 })
	s.actor(&"target", &"puppet", Vector2(500, SHOT), { "max_health": 400.0 })


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
## least `BEYOND` px off the wall line, with no collider and no shadow.
func _lies_beyond(t: TestContext, door: Node2D, dir_x: float, what: String) -> void:
	t.check(door.is_down(), "%s: it is down" % what)
	t.check(
		(door.global_position.x - 400.0) * dir_x >= BEYOND,
		"%s: its middle is %.0f px off the wall line" % [what, door.global_position.x - 400.0],
	)
	t.check(door.collision_layer == 0, "%s: it has no collider" % what)
	t.check(
		door.find_children("*", "LightOccluder2D", true, false).is_empty(),
		"%s: it casts no shadow" % what,
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
	puppet.walk_to(Vector2(500, WALKED_ROW))
	t.check(
		await t.until(func(): return t.actor(&"walker").global_position.x > 480.0, 4.0),
		"a puppet walks over the fallen door and through the doorway (x %.0f)"
			% t.actor(&"walker").global_position.x,
	)


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
		await t.until(sees, 2.0),
		"and sees through the doorway once the door is down",
	)


## An ajar door felled by a kick from its pull side (the strike shoves it toward shut, then deals
## its damage, as a boot does) lies where it fell: the shove that turned the leaf toward shut does
## not carry on and put the fallen leaf back on its hinge.
func _stays_down(t: TestContext) -> void:
	var door = t.object(&"ajar_kicked")
	door.apply_impulse(Vector2.LEFT * KICK_IMPULSE)
	door.take_damage(1000.0)
	await t.frames(2)
	t.check(door.is_down(), "a kick from the pull side fells the ajar door")
	var lies: Vector2 = door.global_position
	var turned: float = door.global_rotation
	await t.seconds(0.5)
	t.check(
		door.global_position.distance_to(lies) < 0.5
		and is_equal_approx(door.global_rotation, turned),
		"and it stays where it fell (moved %.1f px)" % door.global_position.distance_to(lies),
	)
