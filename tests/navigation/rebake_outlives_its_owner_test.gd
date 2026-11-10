extends GameTest
## A re-bake still in flight when the updater that started it is freed (a world torn down
## mid-bake: a test ending, a match restarting) lands quietly: the updater's landing is a bound
## method, which the landing skips once its object has gone, not a lambda that held the updater.
## A smoke guard of that teardown: the error this replaced ("Bad address index" in the updater's
## lambda, logged into whatever test ran next) showed one run in ten in
## `ai/entry/entry_turned_house` and did not reproduce here, so it is `--repeat=40` of that test
## that shows it gone.


func describe() -> Dictionary:
	return {
		"name": "A re-bake outlives the updater that started it",
		"description": "The updater is freed while its re-bake is in flight; the bake lands "
			+ "without an engine error.",
		"tags": ["navigation", "bake", "rebake", "furniture"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 300))
	s.switch(&"nav.rebake", true)
	s.object(&"shelf", "bookshelf", Vector2(300, 150))


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var found := t.world.find_children("*", "Node", true, false).filter(
		func(n: Node) -> bool:
			var script := n.get_script() as Script
			return script != null and script.resource_path.ends_with("nav_updater.gd")
	)
	if not t.require(found.size() == 1, "the world has its updater"):
		return
	var updater: Node = found[0]
	var shelf: Node2D = t.object(&"shelf")
	shelf.global_position = Vector2(300, 40)
	var started := await t.until(func(): return updater.get("_baking") == true, 10.0)
	if not t.require(started, "the updater starts a re-bake of the moved shelf"):
		return
	updater.free()
	# The bake lands on its frame with nobody to tell; a call into the freed updater would be
	# logged as an error, which fails the test.
	await t.frames(NavBakeConfig.house_frames + 3)
