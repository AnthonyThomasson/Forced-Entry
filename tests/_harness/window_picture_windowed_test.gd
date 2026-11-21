extends GameTest
## Harness self-test (#194 blanktest, windowed only): a batch run that opens a window
## (`tools/run_tests.sh --windowed`, `--shots`) shows each test's world, not the root's flat clear
## colour. The batch's own suite (`GameTestSuite.before`, its session and camera, built as gdUnit
## builds them) plays a few representative tests one after another in one process (an arena test,
## one with actors, a vehicle, a test that builds its own picture); after each, its 3D view, when
## the test has one to show, draws more than one colour and carries meshes, and the second and third
## tests are as drawn as the first.
## A perf test measures its own render (no view of the session's is added to it).

const Suite := preload("res://scenes/testing/game_test_suite.gd")
const Catalog := preload("res://scenes/testing/test_catalog.gd")
## Tests to play: an arena test, one with actors, a vehicle test (each shows the game).
const SHOWN: Array[String] = [
	"physics/blood_decals_cap",
	"ai/combat/aim_at_visible_part",
	"vehicle/pile_finds_a_person_beside_a_many_part_piece",
]
## A test that builds its own picture (left to it), and a perf test (measures its own render).
const OWN := "general/pixel_post_view"
const PERF := "perf/mesh_follower_cost"
## Distinct colours a drawn frame of the view holds, sampled on a 48 x 32 grid (a flat frame holds
## 1).
const DRAWN := 3


func describe() -> Dictionary:
	return {
		"name": "A windowed batch run shows each test's world",
		"description": "The batch's suite plays an arena, an actors and a vehicle test in one "
			+ "process: each one's 3D view draws the world (colours and carried meshes); a test "
			+ "with its own picture gets no view of the session's; windowed only.",
		"tags": ["harness", "render", "windowed"],
		"internal": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	# far from the arenas the nested tests stand on: one navigation map
	s.arena(Rect2(9000, 9000, 200, 200))


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var suite: Node = Suite.new()
	t.world.add_child(suite)
	suite.before()
	var session: Node = suite.get("_session")
	for id in SHOWN:
		await session.start(Catalog.describe(_path(id)))
		var view: CanvasLayer = session.view()
		if t.require(view != null, "%s: the session shows a picture" % id):
			await t.frames(2)
			_check_drawn(t, id, view, session.get("world"))
		await session.close()
	await session.start(Catalog.describe(_path(OWN)))
	t.check(session.view() == null, "%s builds its own picture: the session adds none" % OWN)
	await session.close()
	await session.start(Catalog.describe(_path(PERF)))
	t.check(session.view() == null, "%s measures its own render: the session adds no view" % PERF)
	await session.close()
	suite.after()
	suite.free()


## The view's frame holds colours and the view's world holds meshes.
func _check_drawn(t: TestContext, id: String, view: CanvasLayer, world: Node) -> void:
	RenderingServer.force_draw(false)
	var image: Image = view.shown.get_texture().get_image()
	image.resize(48, 32, Image.INTERPOLATE_NEAREST)
	var colours := {}
	for y in 32:
		for x in 48:
			colours[image.get_pixel(x, y).to_html(false)] = true
	t.check(
		colours.size() >= DRAWN,
		"%s: the view's frame is drawn (%d colours)" % [id, colours.size()],
	)
	# the solid bodies carry their meshes on their twins (in the world the view draws), a piece that
	# never moves has its own under the carrier, a floor or a lying item one under the follower
	var meshes: Array = world.twin_space().find_children("*", "GeometryInstance3D", true, false)
	meshes.append_array(view.viewport.find_children("*", "GeometryInstance3D", true, false))
	t.check(not meshes.is_empty(), "%s: the view's world holds meshes (%d)" % [id, meshes.size()])


func _path(id: String) -> String:
	return "%s/%s%s" % [Catalog.ROOT, id, Catalog.SUFFIX]
