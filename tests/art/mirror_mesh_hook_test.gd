extends GameTest
## The mesh hook (#193, interface 27): a domain that has its own mesh for a body kind registers a
## builder with `MeshCarrier.builders` (kind -> `Callable(body) -> Node3D`) and the carrier shows
## that mesh on the body's twin, standing where the body does; a builder that returns null, and a
## kind with no builder, leave the body shown by nothing (there is no stand-in box).

const AT := Vector2(260, 180)
const OTHER := Vector2(520, 300)


func describe() -> Dictionary:
	return {
		"name": "A domain's own mesh is carried on a body's twin through the carrier's hook",
		"description": "A builder for the furniture kind gives each armchair a mesh of its own "
			+ "that stands on the body; null shows nothing; other kinds show nothing.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"chair", "armchair", AT)
	s.object(&"other", "armchair", OTHER)
	s.actor(&"a", &"puppet", Vector2(120, 400))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	await t.frames(5)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	var seen: Array = []
	mirror.builders[MeshKinds.FURNITURE] = func(body: Node2D) -> Node3D:
		seen.append(body)
		if body.name == t.object(&"other").name:
			return null
		var own := MeshInstance3D.new()
		own.name = "OwnMesh"
		own.mesh = SphereMesh.new()
		return own
	view.add_child(mirror)
	mirror.carry(t.world)
	await t.frames(3)
	var chair := t.object(&"chair")
	var proxies := mirror.proxies_of(chair)
	t.require(seen.has(chair), "the builder was asked for the armchair")
	if t.require(proxies.size() == 1, "the armchair has one node") and proxies[0].name == "OwnMesh":
		var at := proxies[0].global_position
		t.expect_near(at.x, AT.x, 1.0, "the domain's mesh stands on the body (x)")
		t.expect_near(at.z, AT.y, 1.0, "the domain's mesh stands on the body (z)")
	else:
		t.check(false, "the armchair is shown by the builder's own mesh")
	var other := mirror.proxies_of(t.object(&"other"))
	t.check(other.is_empty(), "a builder that returns null shows the body by nothing")
	var character := mirror.proxies_of(t.actor(&"a"))
	t.check(character.is_empty(), "a kind with no builder shows the body by nothing")
