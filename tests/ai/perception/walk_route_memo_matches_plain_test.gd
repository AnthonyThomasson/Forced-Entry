extends GameTest
## One snapshot build may ask the same doorway-aware walk for several options. The first answer is
## reused for exactly that build, with every field equal to a freshly computed walk; releasing the
## build's token closes the memo, so behaviour-time walks are always worked out afresh (#192 AC12).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const VIEWS_SCRIPT := "res://scenes/ai/perception/agent_door_views.gd"
const START := Vector2(690, 355)
const GOAL := Vector2(300, 150)
const ENTERING := "door_840_190>kitchen"
const BAKE_FRAMES := 600


func describe() -> Dictionary:
	return {
		"name": "A walked-route memo matches plain routes and ends with its build",
		"description": "Within one decision scope an identical walk is computed once and every "
			+ "field equals the plain route, including its entering and held arguments; returned "
			+ "results are safe copies, and a walk outside the scope is computed afresh.",
		"tags": ["ai", "perception", "entry", "path"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)


func run(t: TestContext) -> void:
	var views: RefCounted = (load(VIEWS_SCRIPT) as GDScript).new()
	if not t.require(views.has_method("begin_decision"), "a snapshot build can open the walk memo"):
		return
	views.set_house(t.world.openings, t.rooms)
	views.pass_clear = func(_key: String) -> bool: return false
	views.ordered_approach = true
	var world := t.world.get_world_2d()
	var plain := await _route(t, views, world, false)
	var plain_held := await _route(t, views, world, true)
	if not t.require(not plain.is_empty() and not plain_held.is_empty(), "the avoid maps answer"):
		return

	var _decision: RefCounted = views.begin_decision()
	var before := _queries(views)
	views.walk_route(START, GOAL, world, ENTERING, false)
	var repeated: Dictionary = views.walk_route(START, GOAL, world, ENTERING, false)
	t.expect_eq(repeated, plain, "every field of the repeated walk equals the plain route")
	t.expect_eq(_queries(views), before + 1, "the two identical walks are computed only once")

	var held: Dictionary = views.walk_route(START, GOAL, world, ENTERING, true)
	t.expect_eq(held, plain_held, "the held argument still selects its own plain route")
	t.expect_eq(_queries(views), before + 2, "a different held argument is not a memo hit")

	repeated["path"][0] = Vector2.INF
	repeated["views"].append({ "changed": true })
	var after_mutation: Dictionary = views.walk_route(START, GOAL, world, ENTERING, false)
	t.expect_eq(after_mutation, plain, "a consumer cannot mutate the remembered route")
	t.expect_eq(_queries(views), before + 2, "the safe copy is still a memo hit")

	_decision = null
	var outside: Dictionary = views.walk_route(START, GOAL, world, ENTERING, false)
	t.expect_eq(outside, plain, "the behaviour-time walk still equals the plain route")
	t.expect_eq(_queries(views), before + 3, "releasing the build closes its memo")


## A route once its avoid map has baked, without opening a decision memo.
func _route(t: TestContext, views: RefCounted, world: World2D, held: bool) -> Dictionary:
	for i in BAKE_FRAMES:
		var way: Dictionary = views.walk_route(START, GOAL, world, ENTERING, held)
		if not bool(way["pending"]):
			return way
		await t.frames(1)
	return {}


func _queries(views: RefCounted) -> int:
	return int(views.get("walk_queries"))
