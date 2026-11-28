extends GameTest
## The pixel post's toon look (#193 rule 6, Art, interface 27): every mesh a builder makes with
## `MeshNodes.instance` shares one toon `ShaderMaterial` with a colour of its own per instance, its
## bands taken from the holders: the number of bands from `PixelPostConfig.bands`, how strong each
## is from `ToonLightConfig`. Headless proves the wiring (the shader is compiled windowed only):
## each band of the material reads back as the holder's strength (darkest none, brightest the light
## whole), a retuned band count reaches a material made after it, and differently named bodies
## carry different colours.

const AT := Vector2(260, 180)
const OTHER := Vector2(520, 300)


func describe() -> Dictionary:
	return {
		"name": "Carried meshes share one toon material banded from the toon light's levels",
		"description": "Every plain mesh a builder makes has the shared toon ShaderMaterial; its "
			+ "bands are the strengths of ToonLightConfig.levels and its pool's those of "
			+ "pool_levels; a band count set in PixelPostConfig reaches a new material and is held "
			+ "to 2 to 5; each body has its own colour.",
		"tags": ["carrier", "3d", "render", "pixel"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"chair", "armchair", AT)
	s.object(&"table", "table", OTHER)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(PixelPostConfig, &"bands", 3)  # restored after the test
	s.set_static(ArtSurfaceConfig, &"tone_light", ArtSurfaceConfig.tone_light)


func run(t: TestContext) -> void:
	await t.frames(5)
	var carrier := _carrier(t)
	await t.frames(3)
	var chair := carrier.proxies_of(t.object(&"chair"))
	var table := carrier.proxies_of(t.object(&"table"))
	if not t.require(
		not chair.is_empty() and not table.is_empty(), "the chair and the table are carried"
	):
		return
	var material := (chair[0] as MeshInstance3D).material_override as ShaderMaterial
	if not t.require(material != null, "a carried mesh holds a ShaderMaterial"):
		return
	t.check(
		material.shader != null and material.shader.resource_path.ends_with("toon.gdshader"),
		"it is the toon shader",
	)
	t.check(material == ToonMaterial.shared(), "it is the one shared material")
	t.check(
		(table[0] as MeshInstance3D).material_override == material,
		"every carried mesh shares the one material",
	)
	_check_bands(t, material, 3)
	_check_pool(t, material)
	t.check(
		_colour(chair[0]) != _colour(table[0]),
		"two bodies have two colours (%s, %s)" % [_colour(chair[0]), _colour(table[0])],
	)
	# A retuned count reaches a material made after it, and `refresh` puts it into one made before.
	PixelPostConfig.bands = 4
	var made := ToonMaterial.make()
	_check_bands(t, made, 4)
	PixelPostConfig.bands = 2
	ToonMaterial.refresh(made)
	_check_bands(t, made, 2)
	# The shader's tone table holds five entries and a band needs a step above it: a count outside
	# 2 to 5 would read past the table (or flatten every surface to the shadow tone), so it is held
	# to that range.
	PixelPostConfig.bands = 9
	t.expect_eq(ToonMaterial.make().get_shader_parameter(&"count"), 5, "nine bands are five")
	PixelPostConfig.bands = 1
	t.expect_eq(ToonMaterial.make().get_shader_parameter(&"count"), 2, "one band is two")


## A carrier of the test world in a 3D viewport of its own, its furniture meshes made by
## `MeshNodes.instance` tinted by the body's name.
func _carrier(t: TestContext) -> MeshCarrier:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var carrier := MeshCarrier.new()
	carrier.builders[MeshKinds.FURNITURE] = func(body: Node2D) -> Node3D:
		var hue := float(str(body.name).hash() % 100) / 100.0
		return MeshNodes.instance(BoxMesh.new(), Color.from_hsv(hue, 0.6, 0.8))
	view.add_child(carrier)
	carrier.carry(t.world)
	return carrier


func _colour(node: Node) -> Color:
	return (node as MeshInstance3D).get_instance_shader_parameter(&"base_color")


## The material has `count` bands and its `levels` are the holder's: none in the darkest band, the
## light whole in the brightest, each band above the one below.
func _check_bands(t: TestContext, material: ShaderMaterial, count: int) -> void:
	t.expect_eq(material.get_shader_parameter(&"count"), count, "%d bands" % count)
	var levels: PackedFloat32Array = material.get_shader_parameter(&"levels")
	t.expect_eq(levels[0], 0.0, "the darkest of %d bands is no light" % count)
	t.expect_eq(levels[count - 1], 1.0, "the brightest of %d bands is the light whole" % count)
	for band in range(1, count):
		t.check(
			levels[band] > levels[band - 1],
			"band %d of %d is brighter than the one below" % [band, count],
		)


## A positional light's pool has its own bands: the holder's count and strengths (times the pool's
## strength), the darkest a little light, the brightest the most.
func _check_pool(t: TestContext, material: ShaderMaterial) -> void:
	var rows := ToonLightConfig.pool_levels
	t.expect_eq(material.get_shader_parameter(&"pool_count"), rows.size(), "the pool's bands")
	var levels: PackedFloat32Array = material.get_shader_parameter(&"pool_levels")
	t.expect_near(
		levels[0], float(rows[0]) * ToonLightConfig.pool_strength, 0.0001, "the pool's darkest band"
	)
	t.expect_near(
		levels[rows.size() - 1],
		float(rows[rows.size() - 1]) * ToonLightConfig.pool_strength,
		0.0001,
		"the pool's brightest band",
	)
	t.check(levels[0] > 0.0, "the darkest band of a pool is a little light, not none")
