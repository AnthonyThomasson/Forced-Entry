extends GameTest
## The pixel post's toon look (#193 rule 6, Art, interface 27): every proxy the mirror makes shares
## one toon `ShaderMaterial` with a colour of its own per instance, its bands and tones taken from
## the holders: the number of bands from `PixelPostConfig.bands`, the tones from
## `ArtSurfaceConfig.tones`. Headless proves the wiring (the shader is compiled windowed only):
## each band of the material's ramp reads back as the matching tone of `tones(base)` (shadow,
## base, light for three bands), a retuned band count reaches a new mirror's material, and
## differently named bodies carry different colours.

const AT := Vector2(260, 180)
const OTHER := Vector2(520, 300)
const GREY := Color(0.4, 0.4, 0.4)


func describe() -> Dictionary:
	return {
		"name": "The mirror's proxies share one toon material banded from the Art ramp",
		"description": "Every proxy has the one toon ShaderMaterial; its three bands are the "
			+ "shadow, base and light tones of ArtSurfaceConfig.tones; a band count set in "
			+ "PixelPostConfig reaches the material; each body has its own colour.",
		"tags": ["mirror", "3d", "render", "pixel"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"chair", "armchair", AT)
	s.object(&"table", "table", OTHER)
	s.actor(&"a", &"puppet", Vector2(120, 400))
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(PixelPostConfig, &"bands", 3)  # both are restored after the test
	s.set_static(ArtSurfaceConfig, &"tone_light", ArtSurfaceConfig.tone_light)


func run(t: TestContext) -> void:
	await t.frames(5)
	var mirror := _mirror(t)
	await t.frames(3)
	var chair := mirror.proxies_of(t.object(&"chair"))
	var table := mirror.proxies_of(t.object(&"table"))
	var person := mirror.proxies_of(t.actor(&"a"))
	if not t.require(
			not chair.is_empty() and not table.is_empty() and not person.is_empty(),
			"the chair, the table and the character are mirrored",
	):
		return
	var material := (chair[0] as MeshInstance3D).material_override as ShaderMaterial
	if not t.require(material != null, "a proxy carries a ShaderMaterial"):
		return
	t.check(
		material.shader != null and material.shader.resource_path.ends_with("toon.gdshader"),
		"it is the toon shader",
	)
	for node in table + person:
		t.check(
			(node as MeshInstance3D).material_override == material,
			"every proxy shares the one material (%s)" % node.name,
		)
	_check_bands(t, material, 3, ["shadow", "base", "light"])
	t.check(
		_colour(chair[0]) != _colour(table[0]),
		"two bodies have two colours (%s, %s)" % [_colour(chair[0]), _colour(table[0])],
	)
	# A retuned count and tone reach a mirror built after it.
	PixelPostConfig.bands = 4
	ArtSurfaceConfig.tone_light = 0.3
	var again := _mirror(t)
	await t.frames(3)
	var proxy := again.proxies_of(t.object(&"chair"))[0] as MeshInstance3D
	_check_bands(
		t,
		proxy.material_override as ShaderMaterial,
		4,
		["shadow", "dark", "base", "light"],
	)
	# The shader's tone table holds five entries and a band needs a step above it: a count outside
	# 2 to 5 would read past the table (or flatten every surface to the shadow tone), so it is held
	# to that range.
	PixelPostConfig.bands = 9
	t.expect_eq(ToonMaterial.make().get_shader_parameter(&"count"), 5, "nine bands are five")
	PixelPostConfig.bands = 1
	t.expect_eq(ToonMaterial.make().get_shader_parameter(&"count"), 2, "one band is two")


## A mirror of the test world in a 3D viewport of its own.
func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	mirror.mirror(t.world)
	return mirror


func _colour(node: Node) -> Color:
	return (node as MeshInstance3D).get_instance_shader_parameter(&"base_color")


## The material has `count` bands and each reads, on a grey, as the named tone of `tones(GREY)`
## (a tone is `base * mul + (1 - base) * lift`, the ramp's own form).
func _check_bands(t: TestContext, material: ShaderMaterial, count: int, tones: Array) -> void:
	t.expect_eq(material.get_shader_parameter(&"count"), count, "%d bands" % count)
	var ramp: PackedVector2Array = material.get_shader_parameter(&"ramp")
	var pick: PackedInt32Array = material.get_shader_parameter(&"pick")
	var wanted := ArtSurfaceConfig.tones(GREY)
	for band in count:
		var step := ramp[pick[band]]
		var got := GREY.r * step.x + (1.0 - GREY.r) * step.y
		t.expect_near(
			got, (wanted[tones[band]] as Color).r, 0.002,
			"band %d of %d is the %s tone" % [band, count, tones[band]],
		)
