extends GameTest
## A shape query of the twin space that more than one page of hits fills still reports every body
## (#194): `TwinSpace.intersecting` pages the query, each page's colliders left out
## of the next, so a floor slab or a wall segment under a crowd cannot crowd a body out of the
## answer the way a single `intersect_shape` with a cap does; the caller's own exclusions are kept.

const SPOTS := [
	Vector2(200, 200), Vector2(240, 200), Vector2(280, 200),
	Vector2(200, 240), Vector2(240, 240), Vector2(280, 240),
]


func describe() -> Dictionary:
	return {
		"name": "A paged twin query reports every body it meets",
		"description": "Six chairs under one cylinder: a plain query capped at two hits misses "
			+ "some; the paged one, a page of two, reports all six and leaves an exclusion alone.",
		"tags": ["general", "twin", "3d", "query"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	for i in SPOTS.size():
		s.object(StringName("chair_%d" % i), "chair", SPOTS[i])


func run(t: TestContext) -> void:
	await t.frames(3)
	var space := TwinSpace.space_of(t.object(&"chair_0"))
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 120.0
	cylinder.height = 30.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cylinder
	query.collision_mask = PhysicsLayers.TWIN_WORLD
	query.transform = Transform3D(Basis(), PlanSpace.lift(Vector2(240, 220), 15.0))
	t.check(
		_owners(t, space.intersect_shape(query, 2)).size() < SPOTS.size(),
		"premise: a query capped at two hits does not reach every chair",
	)
	var found := _owners(t, TwinSpace.intersecting(space, query, 2))
	t.expect_eq(found.size(), SPOTS.size(), "the paged query reports all six chairs")
	var kept: Array[RID] = [TwinSpace.twin_for(t.object(&"chair_0")).get_rid()]
	query.exclude = kept
	var without := _owners(t, TwinSpace.intersecting(space, query, 2))
	t.check(
		not without.has(t.object(&"chair_0")) and without.size() == SPOTS.size() - 1,
		"a caller's exclusion is honoured",
	)
	t.check(query.exclude == kept, "and the query's exclusions are left as they were")


## The distinct chairs of the test among the results' owners.
func _owners(t: TestContext, results: Array[Dictionary]) -> Array:
	var chairs: Array = []
	for i in SPOTS.size():
		chairs.append(t.object(StringName("chair_%d" % i)))
	var out: Array = []
	for hit: Dictionary in results:
		var body := TwinSpace.owner_of(hit["collider"])
		if chairs.has(body) and not out.has(body):
			out.append(body)
	return out
