extends UnitSuite
## What a `PartSkin` (Art, `mesh/part_skin.gd`) keeps and follows: once no skin wears a look it
## holds none of its solids or art, however it caches them; and its material takes a tuning change
## as every other toon material does (`ToonMaterial.refresh_all`).


func test_a_solid_and_art_nothing_else_holds_are_freed() -> void:
	var held := _dress_and_drop()
	assert_object((held[0] as WeakRef).get_ref()).is_null()
	assert_object((held[1] as WeakRef).get_ref()).is_null()


func test_refresh_all_reaches_a_skins_material() -> void:
	var bands := PixelPostConfig.bands
	var skin := PartSkin.new(1)
	var material := skin.node.material_override as ShaderMaterial
	PixelPostConfig.bands = 4
	ToonMaterial.refresh_all()
	assert_int(material.get_shader_parameter(&"count")).is_equal(4)
	PixelPostConfig.bands = bands
	ToonMaterial.refresh_all()
	skin.node.free()


## Dresses a skin of one solid with art, drops it, and returns weak refs to the solid and the art.
func _dress_and_drop() -> Array:
	var solid := MeshKit.new().box(
		MeshKit.volume(Rect2(-4, -4, 8, 8), 0, 4), Color.GRAY
	).build()
	var art := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var skin := PartSkin.new(1)
	skin.parts[0].mesh = solid
	skin.parts[0].texture = art
	skin.parts[0].tint = Color(0.5, 0.5, 1.0)
	skin.dress()
	skin.node.free()
	return [weakref(solid), weakref(art)]
