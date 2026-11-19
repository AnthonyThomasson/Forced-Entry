extends GameTest
## A bullet into the seam of two rooms is deterministic (#194 walls3d): the wall they share is built
## once, owned by the room built first, so a ray through it meets one 3D wall and the same one from
## either side, and rounds fired at it from both rooms all strike that one wall (before, two
## coincident colliders tied at the same distance and the tie followed process history).

const WEST := Rect2(0, 0, 400, 300)
const EAST := Rect2(400, 0, 400, 300)
const SHOTS := 4
## Height (px) of the rays: inside the wall, under a doorway's lintel.
const RAY_HEIGHT := 48.0


func describe() -> Dictionary:
	return {
		"name": "A bullet into the seam of two rooms strikes the one wall they share",
		"description": "Two rooms side by side: a level ray through their common wall meets one "
			+ "wall twin, the first room's, from either side; rounds fired at it from each room "
			+ "dent that wall and never the other room's.",
		"tags": ["walls", "twins", "bullets", "worldgen", "seam"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "bedroom", "rect": WEST },
		{ "key": "east", "type": "bedroom", "rect": EAST },
	])
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	s.actor(&"w", &"puppet", Vector2(250, 150), { "start_slot": 3, "max_health": 1_000_000.0 })
	s.actor(&"e", &"puppet", Vector2(550, 150), { "start_slot": 3, "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	await t.frames(3)
	var west := t.world.find_child("West", true, false) as Node2D
	var east := t.world.find_child("East", true, false) as Node2D
	if not t.require(west != null and east != null, "premise: a wall for each room"):
		return
	var from_west := _owners_along(t, Vector2(300, 150), Vector2(500, 150))
	var from_east := _owners_along(t, Vector2(500, 150), Vector2(300, 150))
	t.check(from_west == [west], "a ray from the west meets one wall, the west's: %s" % [from_west])
	t.check(from_east == [west], "a ray from the east meets the same wall: %s" % [from_east])
	t.puppet(&"w").aim_at(t.actor(&"e"))
	t.puppet(&"e").aim_at(t.actor(&"w"))
	await t.seconds(0.4)
	for _i in SHOTS:
		t.puppet(&"w").shoot()
		t.puppet(&"e").shoot()
		await t.seconds(0.5)
	await t.frames(3)
	t.check(
		west.hit_marks().size() >= SHOTS * 2 - 2,
		"the rounds from both rooms dented the owner's wall (%d marks)" % west.hit_marks().size(),
	)
	t.check(
		east.hit_marks().is_empty(),
		"none dented the other room's wall (%d marks)" % east.hit_marks().size(),
	)


## The walls (2D bodies) a level ray from plan point `from` to `to` passes through, in order.
func _owners_along(t: TestContext, from: Vector2, to: Vector2) -> Array:
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(from, RAY_HEIGHT), PlanSpace.lift(to, RAY_HEIGHT), PhysicsLayers.TWIN_WORLD
	)
	var owners: Array = []
	var skip: Array[RID] = []
	for _try in 8:
		var hit := TwinSpace.space_of(t.world).intersect_ray(query)
		if hit.is_empty():
			break
		var owner := TwinSpace.owner_of(hit["collider"])
		if owner != null and owner.has_method(&"wall_segments"):
			owners.append(owner)
		skip.append((hit["collider"] as CollisionObject3D).get_rid())
		query.exclude = skip
	return owners
