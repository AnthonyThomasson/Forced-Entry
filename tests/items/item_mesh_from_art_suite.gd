extends UnitSuite
## Native unit suite (pure logic) for the items' 3D meshes raised from the 2D art (`GunMesh`,
## `GrenadeMesh`, `ItemSolid`, `SpoonArt`; #193 phase 2b): a held gun is the silhouette of its held
## art, as wide and long as the art, standing up, with the flat art on its top, one mesh and one
## material per gun and look; a lying gun is its side profile, flat; a grenade is its art turned
## about its length, its lever a strip on top. Expected sizes are the config rows' (`GunConfig`,
## `GrenadeConfig`), copied. How it looks is judged windowed:
## `items/items_projectile_mesh_windowed`.

const PISTOL := Vector2(5.0, 13.0)
const RIFLE := Vector2(7.0, 36.0)
const RIFLE_FLAT := Vector2(12.0, 38.0)
const FRAG := Vector2(8.0, 10.0)
const SLACK := 0.05


func _art(slot: int) -> ItemArt:
	return ItemRegistry.inventory_for([slot]).values()[0].art


## The highest point (px) of `mesh`'s vertices whose z (px) is in `[from, to]`.
func _top_between(mesh: Mesh, from: float, to: float) -> float:
	var top := -INF
	for v: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if v.z >= from and v.z <= to:
			top = maxf(top, v.y)
	return top


func test_a_held_gun_is_as_wide_and_long_as_its_art_at_its_grip() -> void:
	var rifle := _art(6).held_mesh().get_aabb()
	assert_float(rifle.size.x).is_equal_approx(RIFLE.x, SLACK)
	assert_float(rifle.size.z).is_equal_approx(RIFLE.y, SLACK)
	# The butt is grip_back (13 px) behind the weapon hand's grip, the muzzle ahead of it.
	assert_float(rifle.position.z).is_equal_approx(-13.0, SLACK)
	var pistol := _art(3).held_mesh().get_aabb()
	assert_float(pistol.size.x).is_equal_approx(PISTOL.x, SLACK)
	assert_float(pistol.size.z).is_equal_approx(PISTOL.y, SLACK)


func test_a_held_gun_stands_up_with_its_parts_at_their_own_heights() -> void:
	var mesh := _art(6).held_mesh()
	var stock := _top_between(mesh, -13.0, -6.0)
	var tallest := _top_between(mesh, -13.0, 40.0)
	assert_float(stock).is_greater(0.0)
	assert_float(tallest).is_greater(stock)  # the receiver stands taller than the stock
	# Its barrel is round and lower than the receiver.
	assert_float(_top_between(mesh, 30.0, 40.0)).is_less(tallest)


func test_the_held_gun_wears_its_flat_art_over_the_art_footprint() -> void:
	var art := _art(6)
	var texture := art.held_texture()
	assert_object(texture).is_not_null()
	assert_vector(Vector2(texture.get_size())).is_equal(RIFLE)
	assert_that(art.held_rect()).is_equal(Rect2(-RIFLE.x * 0.5, -13.0, RIFLE.x, RIFLE.y))
	var node := MeshNodes.textured(art.held_mesh(), texture, art.held_rect())
	var material := node.material_override as ShaderMaterial
	assert_object(material.get_shader_parameter(&"albedo_texture")).is_same(texture)
	node.free()


func test_one_mesh_and_one_texture_per_gun_and_look() -> void:
	var a := _art(6)
	var b := _art(6)
	assert_object(a.held_mesh()).is_same(b.held_mesh())
	assert_object(a.held_texture()).is_same(b.held_texture())
	assert_object(_art(3).held_mesh()).is_not_same(a.held_mesh())
	a.style = &"scrap"
	assert_object(a.held_mesh()).is_not_same(b.held_mesh())
	assert_object(a.held_texture()).is_not_same(b.held_texture())


func test_a_lying_gun_is_its_flat_profile_as_thick_as_the_gun_is_wide() -> void:
	var art := _art(6)
	var box := art.dropped_mesh().get_aabb()
	# The profile's art does not fill its whole footprint across; along, it runs to both ends.
	assert_float(box.size.x).is_between(RIFLE.x, RIFLE_FLAT.x)
	assert_float(box.size.z).is_equal_approx(RIFLE_FLAT.y, SLACK)
	assert_float(box.size.y).is_equal_approx(RIFLE.x * ItemMeshConfig.thickness, SLACK)
	assert_vector(Vector2(art.dropped_texture().get_size())).is_equal(RIFLE_FLAT)
	# The other side up is another picture, mirrored, on its own mesh.
	assert_object(art.dropped_texture(true)).is_not_same(art.dropped_texture(false))
	assert_object(art.dropped_mesh(true)).is_not_same(art.dropped_mesh(false))


func test_a_grenade_is_its_art_turned_about_its_length_with_its_lever_on_top() -> void:
	var art := _art(ItemRegistry.FRAG_SLOT)
	var held := art.held_mesh().get_aabb()
	assert_float(held.size.x).is_equal_approx(FRAG.x, SLACK)
	assert_float(held.size.z).is_equal_approx(FRAG.y, SLACK)
	var thrown := art.dropped_mesh().get_aabb()
	assert_float(thrown.size.z).is_equal_approx(FRAG.y, SLACK)
	assert_float(held.size.y).is_greater(thrown.size.y)  # the lever stands off the body
	assert_float(thrown.size.y).is_equal_approx(FRAG.x, 0.5)  # a round body: as tall as wide
	assert_object(art.held_texture()).is_not_same(art.dropped_texture())
	assert_that(art.held_rect().size).is_equal(FRAG)


func test_the_spoon_is_its_art_lying_flat() -> void:
	var spoon := GrenadeSpoon.new().art
	var box := spoon.dropped_mesh().get_aabb()
	assert_float(box.size.z).is_equal_approx(SpoonArt.SIZE.y, SLACK)
	assert_float(box.size.y).is_equal_approx(ItemMeshConfig.spoon_height, SLACK)
	assert_object(spoon.dropped_texture()).is_not_null()


func test_an_item_with_no_art_shows_nothing() -> void:
	var fists := _art(ItemRegistry.FISTS_SLOT)
	assert_object(fists.held_mesh()).is_null()
	assert_object(fists.held_texture()).is_null()
	assert_object(fists.dropped_mesh()).is_null()
