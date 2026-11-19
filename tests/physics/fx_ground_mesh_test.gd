extends GameTest
## The ground the 3D effects lie on (#193 phase 2, Physics): Main hands `PhysicsMeshes.install` a
## `Callable` from a world point to a height offset (Objects' `StreetGround`, a kerb lower on the
## road), and every effect that lies on the floor takes it into its height: a splat, a print, a
## smear, a scorch, a bleed-out pool, a chip that landed, a hit's bit that rests. With none given
## the ground is flat. Asserted at the seams: the layer `PhysicsMeshes.install` adds and its parts.
## The look is judged in a window, `physics_mesh_windowed_test.gd`.

const WOOD := { "color": Color(0.6, 0.4, 0.2), "material": "wood" }
const SCRATCH := "user://settings_fx_ground_mesh_test.json"
## The road is east of this x; its ground is this many px lower than the pavement's.
const EDGE := 600.0
const KERB := 3.0
const PAVEMENT := Vector2(300, 300)
const ROAD := Vector2(800, 300)


func describe() -> Dictionary:
	return {
		"name": "What lies on the 3D floor lies a kerb lower on the road",
		"description": "With a ground callable a splat, print, smear, scorch, pool and a resting "
			+ "bit lie lower on the road than on the pavement by its offset; with none, the same.",
		"tags": ["mirror", "3d", "render", "physics", "ground"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", true)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror, _ground)
	mirror.mirror(t.world)
	_check_ink(t, layer)
	await _check_pool(t, layer)
	await _check_a_bit(t, layer)
	_check_flat(t)


## The ground: a kerb lower east of `EDGE`.
func _ground(at: Vector2) -> float:
	return -KERB if at.x > EDGE else 0.0


## A splat, a print, a smear and a scorch: each lower on the road by the kerb.
func _check_ink(t: TestContext, layer: FxLayer) -> void:
	var low := {}
	for at: Vector2 in [PAVEMENT, ROAD]:
		var throw := BloodThrow.new()
		throw.size = 3.5
		throw.energy = 0.5
		BloodSpawner.splat(t.world, at, throw)
		var decals := BloodDecals.layer(t.world)
		decals.print_at(PackedVector2Array([at, at + Vector2(6, 0), at + Vector2(6, 3)]), 0.85)
		var ribbon := decals.ribbon_begin(at + Vector2(0, 40), 4.0, 0.9)
		decals.ribbon_extend(ribbon, at + Vector2(10, 40), 4.0, 0.9)
		var rect := Rect2(at + Vector2(0, 80), Vector2(10, 10))
		layer.ink.scorch_burned([rect], [Color(0.1, 0.1, 0.1, 0.8)])
	for kind in [
		InkMark.Kind.SPLAT, InkMark.Kind.PRINT, InkMark.Kind.RIBBON, InkMark.Kind.SCORCH,
	]:
		var marks := layer.ink.marks(kind)
		if not t.require(marks.size() == 2, "two marks of kind %d" % kind):
			continue
		var heights := [_lowest(marks[0]), _lowest(marks[1])]
		heights.sort()
		low[kind] = heights
		t.expect_near(
			heights[0], heights[1] - KERB, 0.001, "kind %d lies a kerb lower on the road" % kind
		)


## The lowest y of `mark`.
func _lowest(mark: InkMark) -> float:
	var lowest := INF
	for v in mark.verts:
		lowest = minf(lowest, v.y)
	return lowest


## A pool on the road lies a kerb lower than one on the pavement.
func _check_pool(t: TestContext, layer: FxLayer) -> void:
	var pools := []
	for at: Vector2 in [PAVEMENT, ROAD]:
		var anchor := Node2D.new()
		t.world.add_child(anchor)
		anchor.global_position = at
		pools.append(BloodSpawner.bleed(t.world, anchor, []))
	await t.seconds(0.6)
	var first := layer.pools.decal_of(pools[0])
	var second := layer.pools.decal_of(pools[1])
	if not t.require(first != null and second != null, "both pools have a decal"):
		return
	t.expect_near(second.position.y, first.position.y - KERB, 0.001, "the pool on the road")


## A bit of a hit on the road rests a kerb lower than one on the pavement.
func _check_a_bit(t: TestContext, layer: FxLayer) -> void:
	var rests := []
	for at: Vector2 in [PAVEMENT, ROAD]:
		DebrisSpawner.spawn(at, Vector2.RIGHT, t.world, WOOD)
		await t.seconds(0.8)
		var lowest := INF
		for shown: Array in layer.debris.chips():
			var frame: Transform3D = shown[1]
			if Vector2(frame.origin.x, frame.origin.z).distance_to(at) < 120.0:
				lowest = minf(lowest, frame.origin.y)
		rests.append(lowest)
	if not t.require(rests[0] < INF and rests[1] < INF, "chips lie at both spots"):
		return
	t.check(rests[1] < rests[0] - 0.5 * KERB, "a chip lies lower on the road (%s)" % [rests])


## With no ground, the same splat lies at the same height on both.
func _check_flat(t: TestContext) -> void:
	var world := FxWorld.new()
	t.expect_eq(world.ground_at(ROAD), 0.0, "no callable is a flat ground")
	var bad := FxWorld.new(Callable())
	t.expect_eq(bad.ground_at(PAVEMENT), 0.0, "an invalid one too")


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
