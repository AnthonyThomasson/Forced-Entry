extends GameTest
## The 3D effects draw their luck from a source of their own (#193 phase 2, Physics): a seeded sim
## makes the same global `randf()` sequence whether or not the 3D layer is on, so a seeded 2D match
## and its tests are not changed by the render mode. A burst of hit particles and a grenade's
## blast (the two effects that roll dice for their look) are played with the layer off and on; the
## sequence after them is the same.

const SCRATCH := "user://settings_fx_own_random_test.json"
const AT := Vector2(400, 300)
const SEED := 4242
const DRAWS := 8


func describe() -> Dictionary:
	return {
		"name": "The 3D effects never draw from the global random source",
		"description": "After seeding, a burst and a blast leave the same randf sequence with the "
			+ "3D layer on as off.",
		"tags": ["mirror", "3d", "render", "physics", "random"],
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
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror)
	mirror.carry(t.world)
	var on := _sequence(t)
	t.check(layer.bursts.shown() > 0 and layer.blasts.shown() > 0, "premise: the layer showed")
	PhysicsFxHook.sink = null
	var off := _sequence(t)
	t.expect_eq(on.size(), DRAWS, "premise: a sequence")
	t.expect_eq(on, off, "the same sequence with the layer on and off")


## Seed, play a burst and a blast, and take the next `DRAWS` draws of the global source.
func _sequence(t: TestContext) -> Array:
	seed(SEED)
	var drawn := []
	var hit := HitInfo.new()
	hit.position = AT
	hit.normal = Vector2.RIGHT
	hit.direction = Vector2.LEFT
	hit.height = 40.0
	HitParticles.spawn(
		hit, { "material": "metal", "color": Color(0.6, 0.4, 0.2) }, HitParticles.Kind.IMPACT
	)
	Physics.spawn_explosion(t.world, AT, &"frag")
	for i in DRAWS:
		drawn.append(randf())
	return drawn


func _mirror(t: TestContext) -> MeshCarrier:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	view.add_child(mirror)
	return mirror
