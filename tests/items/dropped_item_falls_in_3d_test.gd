extends GameTest
## G3 for a dropped item (a dead character's weapon, a grenade's spoon): it falls in 3D. Let go from
## hand height over a desk it lands on the desk's top (31 px up) and lies there, not on the floor
## under it; let go over bare floor it falls to the floor and lies at no height.

const DESK := Vector2(300, 100)
const BARE := Vector2(500, 200)
const TOP := 31.0


func describe() -> Dictionary:
	return {
		"name": "A dropped item falls in 3D and lands on top of a desk",
		"description": "An item let go over a desk comes to rest on its top; one let go over bare "
			+ "floor comes to rest on the floor.",
		"tags": ["dropped", "item", "fall", "furniture", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"desk", "desk", DESK)


func run(t: TestContext) -> void:
	await t.frames(3)
	var over := _drop(t, DESK)
	var bare := _drop(t, BARE)
	await t.seconds(3.0)
	t.check(
		float(over.altitude()) > TOP - 4.0 and float(over.altitude()) < TOP + 4.0,
		"over the desk it lies on its top (%.1f px up, the top at %.0f)" % [over.altitude(), TOP],
	)
	t.check(
		absf(over.global_position.x - DESK.x) <= 60.0
			and absf(over.global_position.y - DESK.y) <= 25.0,
		"inside its footprint (%s)" % str(over.global_position.round()),
	)
	t.check(
		float(bare.altitude()) < 1.0,
		"over bare floor it lies on the floor (%.1f px up)" % bare.altitude(),
	)


## Let a pistol go at `at`, from the hand 4 px beside it, and return it.
func _drop(t: TestContext, at: Vector2) -> DroppedItem:
	var dropped := DroppedItem.spawn(ItemRegistry.create(3, 1), 0.0, Vector2.ZERO)
	dropped.place(t.world, at, at + Vector2(4, 0))
	return dropped
