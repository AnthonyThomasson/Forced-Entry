extends GameTest
## D12 (#194): a dead body falls in the 3D twin space, so it slumps over low furniture instead of
## stopping at its footprint. A man shot standing beside the end of a sofa, the blow driving him
## toward it, falls with his trunk over the sofa's rolled arm (28 px high: his hips, 36 px up, clear
## it) and comes to rest on top of it, the arm's top under his chest. The same man shot in the open
## lies flat on the floor.

const CharacterScene := preload("res://scenes/character/character_base.tscn")
const CharacterRagdoll := preload("res://scenes/character/body/character_ragdoll.gd")
const SOFA_AT := Vector2(300, 250)
## The sofa is 120 x 50; its arm at each end stands 28 px high, its seat 18.
const SOFA_HALF := Vector2(60, 25)
const ARM_TOP := 28.0
## Beside the sofa's west end (a body's width off its face), shot toward it.
const BESIDE := Vector2(222, 250)
const OPEN := Vector2(560, 400)


func describe() -> Dictionary:
	return {
		"name": "A body shot beside a low sofa slumps over it",
		"description": "A dead man's ragdoll is swept as spheres in the twin 3D space: knocked "
			+ "toward a sofa's end it lies over the sofa with its chest on the arm's 28 px top; "
			+ "knocked in the open it lies flat.",
		"tags": ["ragdoll", "death", "3d", "furniture", "heights"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.switch(&"audio.sound", false)
	s.object(&"sofa", "sofa", SOFA_AT)


func run(t: TestContext) -> void:
	await t.frames(3)
	var beside := await _kill(t, BESIDE)
	var open := await _kill(t, OPEN)
	if not t.require(
			await t.until(func(): return beside.is_settled() and open.is_settled(), 8.0),
			"both bodies came to rest",
	):
		return
	var chest := beside.point(CharacterRagdoll.CHEST)
	var at := BESIDE + Vector2(chest.x, chest.y)
	t.require(
		absf(at.x - SOFA_AT.x) < SOFA_HALF.x - 8.0 and absf(at.y - SOFA_AT.y) < SOFA_HALF.y,
		"the chest lies over the sofa (at %s)" % str(at.round()),
	)
	var high: float = chest.z * beside.body.height_scale
	t.check(
		high >= ARM_TOP and high <= ARM_TOP + 14.0,
		"on the arm's top (%.1f px up, the top at %.0f)" % [high, ARM_TOP],
	)
	var flat: float = open.point(CharacterRagdoll.CHEST).z * open.body.height_scale
	t.check(flat < 14.0, "in the open the chest lies on the floor (%.1f px up)" % flat)


## Kill a standing unarmed man at `at` with a blow toward +x and return his fall.
func _kill(t: TestContext, at: Vector2) -> CharacterRagdoll:
	var character := CharacterScene.instantiate()
	character.start_slot = ItemRegistry.UNARMED_SLOT
	t.world.add_child(character)
	character.global_position = at
	await t.frames(2)
	var hit := HitInfo.new()
	hit.position = at
	hit.normal = Vector2.LEFT
	hit.direction = Vector2.RIGHT
	hit.damage = 1000.0
	hit.height = 50.0
	character.take_hit(hit)
	return character.anatomy.ragdoll
