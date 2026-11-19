extends GameTest
## A body does not grow into what is over it (#194 chars3d-a, D13): crouched under a beam hung at
## 40 to 60 px, a character cannot stand back up (a standing body is 74 px tall), nor rise to fire
## over cover (a rise there is refused), and may once it has walked out from under it.

const BEAM := Rect2(150, 100, 100, 100)
const UNDER := Vector2(200, 150)


func describe() -> Dictionary:
	return {
		"name": "A crouched character cannot stand up under a beam",
		"description": "Crouched under a beam at 40 to 60 px, standing (74 px) is refused and the "
			+ "posture stays a crouch; the rise to a taller pose is refused too; clear of the beam "
			+ "both are allowed.",
		"tags": ["twins", "3d", "character", "posture", "stance"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 500, 300))
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.actor(&"duck", &"puppet", UNDER)


func run(t: TestContext) -> void:
	await t.frames(3)
	var body := t.actor(&"duck")
	var beam := StaticBody3D.new()
	beam.collision_layer = PhysicsLayers.TWIN_WORLD
	beam.collision_mask = 0
	beam.add_child(TwinShapes.box(BEAM, Transform2D.IDENTITY, 40.0, 60.0))
	t.world.twin_space().add_child(beam)
	await t.frames(2)
	t.require(body.movement.set_posture(&"crouch"), "premise: it crouches")
	await t.frames(2)
	t.check(not body.movement.set_posture(&"stand"), "standing under the beam is refused")
	t.check(body.movement.posture() == &"crouch", "it stays crouched")
	t.check(
		not body.movement.has_room_for(BodyHeights.FIRE_OVER),
		"a rise to the fire-over pose has no room there either",
	)
	t.check(body.movement.has_room_for(BodyHeights.DUCK), "the duck fits")
	body.global_position = Vector2(350, 150)
	await t.frames(3)
	t.check(body.movement.set_posture(&"stand"), "clear of the beam it stands")
	t.check(body.movement.has_room_for(BodyHeights.STAND), "and has the room")
