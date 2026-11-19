extends GameTest
## D12 (#194): a body falls over what is lower than it is and stops at what is taller. A man shot
## beside a fridge (60 x 70 px, taller than he is) with the blow driving him into it never has a
## joint inside the fridge, every frame of his fall: the 3D cast meets its side at every height he
## has.

const CharacterScene := preload("res://scenes/character/character_base.tscn")
const CharacterRagdoll := preload("res://scenes/character/body/character_ragdoll.gd")
const FRIDGE_AT := Vector2(400, 250)
const FRIDGE_HALF := Vector2(30, 35)
## A body's width off the fridge's west face.
const BESIDE := Vector2(352, 250)


func describe() -> Dictionary:
	return {
		"name": "A body shot beside a tall piece stays outside it",
		"description": "A dead man knocked into a fridge, taller than he is, keeps every joint "
			+ "outside the fridge's footprint for the whole of his fall.",
		"tags": ["ragdoll", "death", "3d", "furniture", "heights"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.switch(&"audio.sound", false)
	s.object(&"fridge", "fridge", FRIDGE_AT)


func run(t: TestContext) -> void:
	await t.frames(3)
	var character := CharacterScene.instantiate()
	character.start_slot = ItemRegistry.UNARMED_SLOT
	t.world.add_child(character)
	character.global_position = BESIDE
	await t.frames(2)
	var hit := HitInfo.new()
	hit.position = BESIDE
	hit.normal = Vector2.LEFT
	hit.direction = Vector2.RIGHT
	hit.damage = 1000.0
	hit.height = 50.0
	character.take_hit(hit)
	var ragdoll: CharacterRagdoll = character.anatomy.ragdoll
	var deepest := 0.0
	for _frame in 330:
		await t.frames(1)
		for i in ragdoll.body.point_count():
			var at := BESIDE + Vector2(ragdoll.point(i).x, ragdoll.point(i).y)
			deepest = maxf(deepest, at.x - (FRIDGE_AT.x - FRIDGE_HALF.x))
	t.check(
		deepest <= 0.5,
		"no joint goes past the fridge's west face (deepest %.2f px in)" % deepest,
	)
	t.check(deepest > -4.0, "premise: a joint pressed on the face (%.1f px off it)" % -deepest)
