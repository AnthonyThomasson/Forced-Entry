extends UnitSuite
## Native unit suite (pure logic) for the items' 3D meshes raised from the 2D art (`GunMesh`,
## `GrenadeMesh`, `ItemSolid`, `SpoonArt`; #193 phase 2b): a held gun is the silhouette of its held
## art, as wide and long as the art, standing up, with the flat art on its top, one mesh and one
## texture per gun and look; a lying gun is its side profile, flat; a grenade is its art turned
## about its length, its lever a strip on top. Expected sizes are the config rows' (`GunConfig`,
## `GrenadeConfig`), copied. How it looks is judged windowed:
## `items/items_projectile_mesh_windowed`.

const WeaponArt = preload("res://scenes/items/art/weapon_art.gd")
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
	assert_object(MeshNodes.shown_texture(node)).is_same(texture)
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


## The drawn pixels of `image` in rows below `limit`, and the last drawn row.
func _drawn(image: Image, limit: int) -> Vector2i:
	var count := 0
	var last := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				last = y
				if y < limit:
					count += 1
	return Vector2i(count, last)


## The area (px) the faces of `mesh` that face straight up and lie below z `limit` cover from
## above, and the number of triangles whose winding disagrees with their normal.
func _up_area(mesh: Mesh, limit: float) -> Vector2:
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var area := 0.0
	var against := 0
	var with := 0
	for i in range(0, points.size(), 3):
		var cross := (points[i + 1] - points[i]).cross(points[i + 2] - points[i])
		assert_float(normals[i].length()).is_equal_approx(1.0, 0.001)
		# The engine's front face is clockwise: a triangle's cross product points against its
		# normal.
		if cross.dot(normals[i]) < 0.0:
			with += 1
		else:
			against += 1
		var middle := (points[i].z + points[i + 1].z + points[i + 2].z) / 3.0
		if normals[i].y > 0.99 and middle < limit:
			area += cross.length() * 0.5
	assert_int(against).is_equal(0)  # every face is wound with its normal
	assert_int(with).is_greater(0)
	return Vector2(area, with)


func test_the_top_of_a_held_gun_is_exactly_its_drawn_pixels() -> void:
	for slot: int in [3, 5, 6]:
		var art := _art(slot)
		var image := art.held_texture().get_image()
		var rows := ItemSolid.rows(image)
		var mesh := art.held_mesh()
		# Its round barrel (a cylinder, no flat top) takes the rows from the barrel part on.
		var canvas := PixelCanvas.new(image.get_width(), image.get_height(), 0, Vector2.ZERO)
		var parts := WeaponArt.held_parts(canvas, art.gun, false)
		var barrel_from := image.get_height()
		if parts.has("barrel"):
			barrel_from = (parts["barrel"] as Rect2i).position.y + 1
		var drawn := _drawn(image, barrel_from)
		var limit := art.held_rect().position.y + barrel_from
		assert_float(_up_area(mesh, limit).x).is_equal_approx(float(drawn.x), 0.01)
		# The muzzle leads along +z: the mesh ends where the last drawn row does.
		var ahead := art.held_rect().position.y + float(drawn.y + 1)
		assert_float(mesh.get_aabb().end.z).is_equal_approx(ahead, 0.01)
		assert_int(rows.size()).is_equal(image.get_height())


## The vertices of `mesh` as a set of points rounded to a hundredth of a px, mirrored across x when
## `mirror`.
func _points(mesh: Mesh, mirror: bool) -> Dictionary:
	var points := {}
	for v: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var x := -v.x if mirror else v.x
		points[Vector3(snappedf(x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01))] = true
	return points


func test_a_lying_gun_flipped_is_the_mirror_of_it() -> void:
	var art := _art(6)
	var straight := _points(art.dropped_mesh(false), false)
	var other := _points(art.dropped_mesh(true), false)
	var mirrored := _points(art.dropped_mesh(true), true)
	assert_bool(mirrored.keys().all(func(p: Vector3) -> bool: return straight.has(p))).is_true()
	assert_int(mirrored.size()).is_equal(straight.size())
	# The profile is not symmetric, so the other side up really is the other way round.
	assert_bool(other.keys().all(func(p: Vector3) -> bool: return straight.has(p))).is_false()


func test_a_lying_gun_is_thinner_at_its_barrel_than_at_its_receiver() -> void:
	var mesh := _art(6).dropped_mesh()
	var tallest := _top_between(mesh, -19.0, 19.0)
	assert_float(tallest).is_equal_approx(RIFLE.x * ItemMeshConfig.thickness, 0.01)
	assert_float(_top_between(mesh, 17.0, 19.0)).is_less(tallest)  # the barrel post
	assert_float(_top_between(mesh, -19.0, -17.0)).is_less(tallest)  # the stock


func test_an_item_with_no_art_shows_nothing() -> void:
	var fists := _art(ItemRegistry.FISTS_SLOT)
	assert_object(fists.held_mesh()).is_null()
	assert_object(fists.held_texture()).is_null()
	assert_object(fists.dropped_mesh()).is_null()
