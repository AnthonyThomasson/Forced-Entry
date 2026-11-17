extends GameTest
## The mirror's mesh hook (#193, interface 27): a domain that has its own mesh for a body kind
## registers a builder with `WorldMirror.builders` (kind -> `Callable(body) -> Node3D`) and the
## mirror shows that mesh in place of the kind's proxies, following the body's whole transform; a
## builder that returns null keeps the proxy, and a kind with no builder is untouched. This is what
## phase 2's meshes plug into.

const AT := Vector2(260, 180)
const OTHER := Vector2(520, 300)


func describe() -> Dictionary:
	return {
		"name": "A domain's own mesh replaces a body kind's proxy through the mirror's hook",
		"description": "A builder for the furniture kind gives each armchair a mesh of its own "
			+ "that follows the body; null keeps the proxy; other kinds keep theirs.",
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
	var mirror := WorldMirror.new()
	var seen: Array = []
	mirror.builders[MirrorProxy.FURNITURE] = func(body: Node2D) -> Node3D:
		seen.append(body)
		if body.name == t.object(&"other").name:
			return null
		var own := MeshInstance3D.new()
		own.name = "OwnMesh"
		own.mesh = SphereMesh.new()
		return own
	view.add_child(mirror)
	mirror.mirror(t.world)
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
	t.check(
		other.size() == 1 and other[0].name != "OwnMesh",
		"a builder that returns null leaves the proxy",
	)
	var character := mirror.proxies_of(t.actor(&"a"))
	t.check(
		character.size() == 1 and (character[0] as MeshInstance3D).mesh is CapsuleMesh,
		"a kind with no builder keeps its proxy",
	)
