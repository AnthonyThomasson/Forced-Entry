extends GameTest
## The hit particles of a 3D match (#193 phase 2, Physics): a burst `HitParticles` makes is as many
## small cubes as the burst's `amount`, in its colour and sizes, flung off the surface at
## the hit's height within its cone and speeds, falling to the floor and shrinking away within its
## life; the metal style's sparks are lit whatever the light. Sustained fire fills a pool that is
## bounded, makes no new node or mesh, and when it is over nothing runs or is written. Asserted at
## the seams: the layer `PhysicsMeshes.install` adds and the burst `HitParticles` tells it. The
## numbers are pinned here; the look is judged in a window, `physics_mesh_windowed_test.gd`.

const SCRATCH := "user://settings_hit_particles_mesh_test.json"
const AT := Vector2(400, 300)
## A hit's 0..100 height is this many px (a wall's 100 is 96); a bit on the floor lies this high.
const HEIGHT_PX := 0.96
const REST := 2.1
## The wood style (`HitParticles.STYLES`): the size of a bit (px), its cone (degrees either side),
## and the longest a bit lives (s). A lone impact is a full-strength burst: its speed is 1.3 times
## the style's.
const WOOD_SIZE := Vector2(1.5, 3.5)
const WOOD_SPREAD := 55.0
const WOOD_LIFE := 0.45
const WOOD_FASTEST := 150.0 * 1.3
## The pool's size, pinned for the sustained-fire part.
const BITS := 40
const SPARKS := 16


func describe() -> Dictionary:
	return {
		"name": "A hit's particles are tiny cubes that fly from the hit and shrink away",
		"description": "A burst is as many cubes as its `amount`, in its colour "
			+ "and sizes, flung off the surface at the hit's height within its cone and speed; "
			+ "the metal style's sparks glow; a pool bounds sustained fire; nothing runs at rest.",
		"tags": ["mirror", "3d", "render", "physics", "hit particles"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(PhysicsMeshConfig, &"bit_capacity", BITS)
	s.set_static(PhysicsMeshConfig, &"spark_capacity", SPARKS)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror)
	mirror.mirror(t.world)
	t.expect_eq(layer.bursts.shown(), 0, "no burst, no bit")
	await _check_a_burst(t, layer)
	await _check_sparks(t, layer)
	await _check_sustained_fire(t, layer)


## A wooden hit: its bits, where they start, how they fly and when they are gone.
func _check_a_burst(t: TestContext, layer: FxLayer) -> void:
	var burst := _burst(t, "wood", 50.0)
	t.expect_eq(layer.bursts.shown(), burst["amount"], "a bit for each particle of the burst")
	var pieces := layer.bursts.pieces()
	var colour: Color = burst["color"]
	var way := Vector2.RIGHT
	for piece in pieces:
		var frame := layer.bursts.bits().frame_of(piece)
		t.check(piece.color.is_equal_approx(colour), "in the burst's colour")
		t.check(piece.size.x >= WOOD_SIZE.x and piece.size.x <= WOOD_SIZE.y, "within its sizes")
		t.expect_near(frame.origin.y, REST + 50.0 * HEIGHT_PX, 0.5, "flung off the hit's height")
		t.expect_near(
			Vector2(frame.origin.x, frame.origin.z).distance_to(AT), 0.0, 0.5, "from the hit"
		)
		t.check(
			rad_to_deg(absf(piece.velocity.angle_to(way))) <= WOOD_SPREAD + 0.01,
			"within the cone of the burst",
		)
		t.check(piece.velocity.length() <= WOOD_FASTEST + 0.01, "no faster than the style's")
	var farthest := 0.0
	var lowest := INF
	for _i in 30:
		await t.frames(1)
		for piece in layer.bursts.pieces():
			var frame := layer.bursts.bits().frame_of(piece)
			farthest = maxf(farthest, Vector2(frame.origin.x, frame.origin.z).distance_to(AT))
			lowest = minf(lowest, frame.origin.y)
	t.check(farthest > 10.0, "the bits fly out (%.0f px)" % farthest)
	t.check(farthest < WOOD_FASTEST * WOOD_LIFE, "but no farther than they can (%.0f)" % farthest)
	t.check(lowest >= REST - 0.01, "and never through the floor (%.2f)" % lowest)
	await t.seconds(WOOD_LIFE + 0.2)
	t.expect_eq(layer.bursts.shown(), 0, "within its life the burst is gone")
	t.check(not layer.is_processing(), "and the layer rests")
	var wrote := layer.bursts.bits().writes
	await t.frames(10)
	t.expect_eq(layer.bursts.bits().writes, wrote, "nothing is written once it is over")


## A metal hit: sparks, lit whatever the light, in a batch of their own.
func _check_sparks(t: TestContext, layer: FxLayer) -> void:
	var burst := _burst(t, "metal", -1.0)
	t.expect_eq(layer.bursts.sparks().count(), burst["amount"], "a spark for each particle")
	t.expect_eq(layer.bursts.bits().count(), 0, "and no other bit")
	var glow: Variant = layer.bursts.sparks().node.get_instance_shader_parameter(&"emissive")
	t.check(glow != null and glow.a > 0.0 and glow.r > 0.0, "a spark glows")
	var plain: Variant = layer.bursts.bits().node.get_instance_shader_parameter(&"emissive")
	t.check(plain == null or plain.a <= 0.0, "a bit of wood does not")
	for piece in layer.bursts.pieces():
		var frame := layer.bursts.sparks().frame_of(piece)
		t.expect_near(frame.origin.y, REST, 0.5, "a hit with no height throws from the floor")
	await t.seconds(0.6)
	t.expect_eq(layer.bursts.shown(), 0, "the sparks go out")


## Sustained fire: more bursts than the pool holds. It is never over its size, and nothing new is
## made.
func _check_sustained_fire(t: TestContext, layer: FxLayer) -> void:
	var nodes := layer.get_child_count()
	var builds := MeshCache.builds
	var peak := 0
	for i in 60:
		_burst(t, "metal" if i % 2 == 0 else "wood", 30.0)
		await t.frames(1)
		peak = maxi(peak, layer.bursts.bits().count())
		t.check(layer.bursts.bits().count() <= BITS, "the bits are never over their pool")
		t.check(layer.bursts.sparks().count() <= SPARKS, "nor the sparks")
	t.expect_eq(peak, BITS, "the pool fills (bits die as others are born, so the peak)")
	await t.seconds(1.0)
	t.expect_eq(layer.bursts.shown(), 0, "and when the fire stops it all goes")
	t.expect_eq(layer.get_child_count(), nodes, "no node was made")
	t.expect_eq(MeshCache.builds, builds, "no mesh was made")
	t.check(not layer.is_processing(), "and nothing runs")


## One burst of `material` at `AT` on a surface facing +x, struck at `height`.
func _burst(_t: TestContext, material: String, height: float) -> Dictionary:
	var hit := HitInfo.new()
	hit.position = AT
	hit.normal = Vector2.RIGHT
	hit.direction = Vector2.LEFT
	hit.height = height
	var surface := { "material": material, "color": Color(0.6, 0.4, 0.2) }
	return HitParticles.spawn(hit, surface, HitParticles.Kind.IMPACT)


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
