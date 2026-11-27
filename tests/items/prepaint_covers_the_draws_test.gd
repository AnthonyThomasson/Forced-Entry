extends GameTest
## Every gun and grenade an inventory makes warms what the 3D render shows of it ahead of time
## (`ItemArt.prepaint`, from `ItemRegistry.inventory_for`): its held and loose meshes and flat art,
## so no first build or paint lands in the busiest frames of a fight. This makes each weapon style's
## guns and grenades, then asks for every mesh and texture a match shows of them (held, lying either
## side up): no mesh is built and no texture painted anew, and the art handed out is the same
## object the second time (the caches hold it). The art is in the toon's atlas too, the thrown
## grenade's spoon with it, so a gun first dropped mid-fight costs no readback or page write. (The
## atlas is the process's: run this test on its own to see a missing warm.)

const STYLES: Array[StringName] = [&"police", &"scrap", &"pipe"]


func describe() -> Dictionary:
	return {
		"name": "Prepainted weapon art covers every mesh and texture shown",
		"description": "After ItemRegistry makes guns and grenades in each style, asking for "
			+ "their held and lying meshes and art builds and paints nothing new, and the art is "
			+ "already in the toon's atlas.",
		"tags": ["art", "gun", "grenade", "cache"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var items := _make_items(t)
	_check_atlased(t, items)
	var built := MeshCache.builds
	var painted := PixelArt._cache.size()
	var shown := 0
	for item: Item in items:
		for flip in [false, true]:
			for mesh: Mesh in [item.art.held_mesh(), item.art.dropped_mesh(flip)]:
				shown += 1 if mesh != null else 0
			for tex: Texture2D in [item.art.held_texture(), item.art.dropped_texture(flip)]:
				shown += 1 if tex != null else 0
	t.check(shown > items.size(), "the items show meshes and art (%d of them)" % shown)
	t.check(
		MeshCache.builds == built,
		"no mesh was built when a match asks for them (%d new)" % (MeshCache.builds - built),
	)
	t.check(
		PixelArt._cache.size() == painted,
		"no texture was painted when a match asks for them (%d new)"
			% (PixelArt._cache.size() - painted),
	)
	for item: Item in items:
		t.check(
			item.art.held_texture() == item.art.held_texture(),
			"%s hands out the same held art each time" % item.get_script().resource_path,
		)


## Every texture the items show, and the spoon's, is already in the toon's atlas.
func _check_atlased(t: TestContext, items: Array) -> void:
	var cold := 0
	for item: Item in items:
		for flip in [false, true]:
			for tex: Texture2D in [item.art.held_texture(), item.art.dropped_texture(flip)]:
				cold += 1 if tex != null and not ToonAtlas.holds(tex) else 0
	t.expect_eq(cold, 0, "the items' art is in the atlas once they are made")
	t.check(
		ToonAtlas.holds(SpoonArt.new().dropped_texture()),
		"and so is the spoon a thrown grenade lets go",
	)


## Every style's guns and grenades, made by `ItemRegistry.inventory_for` (which prepaints them).
func _make_items(t: TestContext) -> Array:
	var slots := ItemRegistry.gun_slots() + [ItemRegistry.STUN_SLOT, ItemRegistry.FRAG_SLOT]
	var items: Array = []
	for style in STYLES:
		var inv := ItemRegistry.inventory_for(
			slots,
			-1,
			&"",
			{ ItemRegistry.STUN_SLOT: 1, ItemRegistry.FRAG_SLOT: 1 },
			style,
		)
		for item in inv.values():
			items.append(item)
	var guns := items.filter(func(item: Item) -> bool: return item is GunItem).size()
	var grenades := items.filter(func(item: Item) -> bool: return item is GrenadeItem).size()
	t.check(
		guns >= 3 * STYLES.size() and grenades == 2 * STYLES.size(),
		"every style's guns and grenades were made (%d guns, %d grenades)" % [guns, grenades],
	)
	return items
