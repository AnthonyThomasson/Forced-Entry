extends GameTest
## The debris of a 3D match (#193 phase 2, Physics): a chip `DebrisSpawner` throws is one part of a
## batch in the colour, size and shape of its 2D chip. It leaves the surface at the hit's height
## and follows its 2D node down to the floor along an arc, then lies where its node came to rest,
## written once and never again; what lies is kept up to the `Despawner`'s cap as `DebrisLayer`
## keeps it, so sustained fire is bounded and makes no new mesh. Asserted at the seams: the layer
## `PhysicsMeshes.install` adds and the 2D chips and `DebrisLayer` it mirrors. The numbers are
## pinned here; the look is judged in a window, `physics_mesh_windowed_test.gd`.

const SCRATCH := "user://settings_debris_mesh_test.json"
## A chip lies this high (px): over the blood and the scorch that lie on the floor.
const REST := 2.1
## A chip is this thick (px); a thrown one arcs this high (px) over the line from where it left to
## where it lies.
const THICK := 1.0
const ARC := 9.0
## A hit's height is px; the test scales it (`PhysicsMeshConfig.height_scale`) so a mesh that
## ignored the scale would show.
const HEIGHT_PX := 2.0
## How far (px) a flying chip may be from its node: the tween moves the node after the layer runs,
## so the part is a frame behind it, at most 7 px at the throw's fastest (50 px in a quarter second,
## eased out, is 400 px/s at first).
const SLACK := 7.0
const AT := Vector2(300, 300)
## The chips in the air besides those that lie (`PhysicsMeshConfig.flying_room`).
const ROOM := 256
## The `Despawner`'s cap for the sustained-fire part.
const KEPT := 30


func describe() -> Dictionary:
	return {
		"name": "A chip is a tiny mesh that flies from the hit and lies on the 3D floor",
		"description": "A chip takes its 2D chip's colour, size and shape, leaves the surface at "
			+ "the hit's height, follows its node down along an arc and lies where it rests; what "
			+ "lies is bounded by the Despawner's cap, and nothing is written once it all lies.",
		"tags": ["mirror", "3d", "render", "physics", "debris"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(PhysicsMeshConfig, &"height_scale", HEIGHT_PX)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	var kept := Despawner.max_scene_objects
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror)
	mirror.mirror(t.world)
	t.check(layer.debris.shown() == 0, "no chip, none shown")
	await _check_one_hit(t, layer)
	Despawner.max_scene_objects = KEPT
	var capped := PhysicsMeshes.install(mirror)
	await _check_sustained_fire(t, capped)
	Despawner.max_scene_objects = kept


## One hit on a wall at a height: its chips are shown as they fly and where they lie.
func _check_one_hit(t: TestContext, layer: FxLayer) -> void:
	PhysicsFxHook.hit_height = 50.0
	DebrisSpawner.spawn(AT, Vector2.RIGHT, t.world, Color(0.6, 0.4, 0.2), "wood")
	PhysicsFxHook.hit_height = -1.0
	var chips := _chips(t)
	t.check(chips.size() >= 3 and chips.size() <= 6, "a wooden hit throws 3 to 6 chips")
	t.expect_eq(layer.debris.shown(), chips.size(), "each chip is shown")
	t.expect_eq(layer.debris.flying(), chips.size(), "all in the air")
	for shown: Array in layer.debris.chips():
		_check_leaving(t, shown[0], shown[1])
	await _check_flight(t, layer)
	await t.seconds(0.6)
	t.expect_eq(layer.debris.flying(), 0, "after its throw none is in the air")
	_check_lying(t, layer)
	t.check(not layer.is_processing(), "and the layer rests")
	var wrote := layer.debris.writes()
	var builds := MeshCache.builds
	await t.frames(10)
	t.expect_eq(layer.debris.writes(), wrote, "a chip at rest is written no more")
	t.expect_eq(MeshCache.builds, builds, "no new mesh is made")


## A chip as it leaves: its 2D chip's colour and size, the hit's height, a chip's thickness.
func _check_leaving(t: TestContext, piece: FxPiece, frame: Transform3D) -> void:
	var node := _node_of(piece)
	if not t.require(node != null, "a chip follows a 2D chip"):
		return
	t.check(piece.color.is_equal_approx(node.color), "in its colour")
	t.expect_near(piece.size.x, node.chip_size.x, 0.001, "as wide")
	t.expect_near(frame.origin.y, REST + 50.0 * HEIGHT_PX, 0.01, "leaving at the hit's height")
	t.expect_near(frame.basis.y.length(), THICK, 0.01, "as thick as a chip")


## The chips in the air stay with their nodes.
func _check_flight(t: TestContext, layer: FxLayer) -> void:
	var worst := 0.0
	for _i in 30:
		await t.frames(1)
		for shown: Array in layer.debris.chips():
			var frame: Transform3D = shown[1]
			var node := _node_of(shown[0])
			if node != null:
				var at := Vector2(frame.origin.x, frame.origin.z)
				worst = maxf(worst, at.distance_to(node.global_position))
	t.check(worst < SLACK, "in the air it follows its node (off by up to %.1f px)" % worst)


## The chips that lie: on the floor, each where a 2D chip lies, as many as the 2D layer keeps.
func _check_lying(t: TestContext, layer: FxLayer) -> void:
	var layer2d := DebrisLayer.find(t.world)
	var lying: Array = layer2d.items() if layer2d != null else []
	t.expect_eq(layer.debris.lying(), lying.size(), "the chips lie as many as the 2D layer keeps")
	for shown: Array in layer.debris.chips():
		var frame: Transform3D = shown[1]
		t.expect_near(frame.origin.y, REST, 0.01, "a lying chip is on the floor")
		var at := Vector2(frame.origin.x, frame.origin.z)
		var found := lying.any(func(m: Dictionary) -> bool: return m["at"].distance_to(at) < 0.1)
		t.check(found, "where a 2D chip lies (%s)" % at)


## Sustained fire: far more chips than the world keeps. The world keeps `KEPT` and so does the
## batch, in the cap's own order, and nothing grows.
func _check_sustained_fire(t: TestContext, layer: FxLayer) -> void:
	for i in 60:
		DebrisSpawner.spawn(AT + Vector2(i % 20, 0), Vector2.UP, t.world, Color.GRAY, "metal")
		await t.frames(1)
		t.check(layer.debris.shown() <= KEPT, "the layer is never over the cap")
	await t.seconds(0.6)
	var kept_2d := DebrisLayer.find(t.world).count()
	t.check(
		kept_2d > 0 and kept_2d <= KEPT,
		"the 2D layer keeps chips, within the cap (%d)" % kept_2d,
	)
	t.expect_eq(layer.debris.lying(), kept_2d, "the layer shows the chips the 2D layer keeps")
	t.expect_eq(layer.debris.shown(), kept_2d, "and none in the air")
	for shape: String in ["rect", "tri", "circle"]:
		t.expect_eq(
			layer.debris.batch_of(shape).capacity(),
			KEPT + ROOM,
			"a batch is the cap of chips that lie and the room for those in the air",
		)
	t.check(not layer.is_processing(), "nothing runs once they all lie")


## The 2D chips in the world (the flying ones are its direct children).
func _chips(t: TestContext) -> Array:
	return t.world.get_children().filter(func(n: Node) -> bool:
		var script: Script = n.get_script()
		return script != null and script.resource_path.ends_with("physics/debris.gd"))


## The 2D chip `piece` follows.
func _node_of(piece: FxPiece) -> Node2D:
	var node: Variant = instance_from_id(piece.node_id)
	return node as Node2D if is_instance_valid(node) else null


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
