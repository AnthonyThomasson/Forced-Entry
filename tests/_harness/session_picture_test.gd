extends GameTest
## Harness self-test: the picture a test session shows (#193) is of the open test's world only. A
## test that declares no world stands on the default arena; when it builds a district of its own
## into the world, the arena it replaces is out of the picture (its floor would otherwise be drawn
## over the district's), the district is in it, and a test's view is gone with its test: after
## `close()` the session holds no view and the mirror is freed.

const SessionScript = preload("res://scenes/testing/test_session.gd")
const Catalog = preload("res://scenes/testing/test_catalog.gd")
const Fixture = preload("res://tests/_harness/picture_fixtures/own_world_fixture.gd")
const FIXTURE_PATH := "res://tests/_harness/picture_fixtures/own_world_fixture.gd"


func describe() -> Dictionary:
	return {
		"name": "The session's picture shows only the open test's world",
		"tags": ["harness", "render"],
		"internal": true,
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	# far from the fixture's world: both are on the one navigation map
	s.arena(Rect2(9000, 9000, 200, 200))


func run(t: TestContext) -> void:
	Fixture.built = false
	var session := SessionScript.new()
	session.picture = true
	t.world.add_child(session)
	var camera := Camera2D.new()
	camera.position = Vector2(400, 700)
	session.add_child(camera)
	camera.make_current()
	session.start(Catalog.describe(FIXTURE_PATH))
	var built: bool = await t.until(func() -> bool: return Fixture.built, 6.0)
	if not t.require(built, "premise: the district is built"):
		session.queue_free()
		return
	await t.frames(4)
	var view := session.view()
	if not t.require(view != null, "premise: the session shows a picture"):
		session.queue_free()
		return
	var mirror: MeshCarrier = view.get("carrier")
	_check_shown(t, session, mirror)
	await t.until(func() -> bool: return session.ctx != null and session.ctx.is_finished, 6.0)
	var closed: Variant = weakref(mirror)
	await session.close()
	await t.frames(2)
	t.check(session.view() == null, "after close() the session holds no view")
	t.expect_eq(
		session.find_children("*", "MeshCarrier", true, false).size(), 0, "and no mirror node",
	)
	t.check(closed.get_ref() == null, "the mirror is freed")
	session.queue_free()


## The arena the test replaced is out of the picture, its district and its actor are in.
func _check_shown(t: TestContext, session: Node, mirror: MeshCarrier) -> void:
	var arena_floors := _floors(session.world.house)
	var district_floors := _floors(Fixture.district)
	t.require(
		not arena_floors.is_empty() and not district_floors.is_empty(),
		"premise: both have floors",
	)
	t.check(
		arena_floors.all(func(f: Node) -> bool: return mirror.proxies_of(f).is_empty()),
		"the default arena the test replaced is not in the picture",
	)
	t.check(
		district_floors.any(func(f: Node) -> bool: return not mirror.proxies_of(f).is_empty()),
		"the district it built is",
	)
	t.check(
		not mirror.proxies_of(session.world.actors[&"me"]).is_empty(),
		"and so is the test's own actor",
	)


## Every floor under `root`.
func _floors(root: Node) -> Array:
	return root.find_children("*", "", true, false).filter(
		func(n: Node) -> bool: return n.is_in_group(&"floors")
	)
