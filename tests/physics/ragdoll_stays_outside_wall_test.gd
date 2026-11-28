extends GameTest
## D12 (#194): a dead body falls against a wall at its real height and stays outside it. A man shot
## beside the arena's west wall, the blow driving him into it, lies with every joint on this side of
## the wall's face; a man shot in a corner stays out of both walls.

const CharacterScene := preload("res://scenes/character/character_base.tscn")
const CharacterRagdoll := preload("res://scenes/character/body/character_ragdoll.gd")
## The arena's wall is 12 px thick, centred on its edge: the inner face is 6 px in.
const FACE := 6.0
const WEST := Vector2(24, 250)
const CORNER := Vector2(26, 26)
## The smallest joint's radius (a hand, a foot): the least its centre may be off a wall.
const SMALLEST := 3.3


func describe() -> Dictionary:
	return {
		"name": "A body shot against a wall stays outside it",
		"description": "A dead man's joints, knocked into the west wall or a corner, all rest on "
			+ "this side of the wall's face: the falling body is swept against the walls' 3D "
			+ "twins at every height.",
		"tags": ["ragdoll", "death", "3d", "wall"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.switch(&"audio.sound", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var west := await _kill(t, WEST, Vector2.LEFT)
	var corner := await _kill(t, CORNER, Vector2(-1.0, -1.0))
	# A fall runs five seconds at most: sample the whole of it, every frame.
	var worst := {}
	for _frame in 330:
		await t.frames(1)
		for case in [["west", west, WEST], ["corner", corner, CORNER]]:
			var ragdoll: CharacterRagdoll = case[1]
			for i in ragdoll.body.point_count():
				var p: Vector3 = ragdoll.point(i)
				var at: Vector2 = case[2] + Vector2(p.x, p.y)
				var least := minf(at.x, at.y)
				if least < float(worst.get(case[0], INF)):
					worst[case[0]] = least
	for name: String in worst:
		# The smallest joint is 3.3 px across: its centre stays that far off the wall's face.
		t.check(
			float(worst[name]) >= FACE + SMALLEST,
			"the %s body's joints stay out of the walls (nearest %.2f px past the face)"
				% [name, float(worst[name]) - FACE],
		)


func _kill(t: TestContext, at: Vector2, blow: Vector2) -> CharacterRagdoll:
	var character := CharacterScene.instantiate()
	character.start_slot = ItemRegistry.UNARMED_SLOT
	t.world.add_child(character)
	character.global_position = at
	await t.frames(2)
	var hit := HitInfo.new()
	hit.position = at
	hit.normal = -blow
	hit.direction = blow.normalized()
	hit.damage = 1000.0
	hit.height = 50.0
	character.take_hit(hit)
	return character.anatomy.ragdoll
