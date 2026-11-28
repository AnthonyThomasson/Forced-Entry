extends GameTest
## A new carrier (the view's mirror, built once per view) pushes the toon holders into the materials
## that already live (`ToonMaterial.refresh_all`), so a tuning change applies from the next match
## (#194, Art, interface 27): the shared material, a decal's, a textured one in the atlas, the still
## chunks' merged one and a `PartSkin`'s.

const RETUNED_BANDS := 2


func describe() -> Dictionary:
	return {
		"name": "A new carrier puts a retuned toon holder into the materials that live",
		"description": "The shared, decal, atlas textured, merged-chunk and part-skin materials "
			+ "keep their band count when the holder is retuned, and read the new one once a new "
			+ "MeshCarrier is built.",
		"tags": ["carrier", "3d", "render", "pixel"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.set_static(PixelPostConfig, &"bands", 3)  # restored after the test


func run(t: TestContext) -> void:
	await t.frames(1)
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	# held for the whole test: a decal's and a part skin's materials are held weakly
	var skin := PartSkin.new(1)
	var materials := {
		"shared": ToonMaterial.shared(),
		"decal": ToonMaterial.decal(texture),
		"textured": ToonMaterial.textured(texture),
		"merged": ToonMaterial.merged(),
		"part skin": skin.node.material_override,
	}
	# the materials may predate this test (the shared and merged ones are held for good)
	ToonMaterial.refresh_all()
	for kind: String in materials:
		_check(t, materials[kind], 3, "the %s material before" % kind)
	PixelPostConfig.bands = RETUNED_BANDS
	for kind: String in materials:
		_check(t, materials[kind], 3, "the %s material, no new carrier yet," % kind)
	var carrier := MeshCarrier.new()
	for kind: String in materials:
		_check(t, materials[kind], RETUNED_BANDS, "the %s material, a new carrier," % kind)
	carrier.free()
	skin.node.free()  # never shown: only its material is read
	PixelPostConfig.bands = 3
	ToonMaterial.refresh_all()  # the materials outlive the test: no later one reads its bands


func _check(t: TestContext, material: ShaderMaterial, bands: int, what: String) -> void:
	t.expect_eq(material.get_shader_parameter(&"count"), bands, "%s has %d bands" % [what, bands])
