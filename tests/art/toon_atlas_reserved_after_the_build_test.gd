extends GameTest
## The pages `build_all` opens in the toon's atlas (a merged decal's art is copied in there) are
## covered by the spare: the view asks for it again (`ToonAtlas.reserve`) after the chunks are
## built, not only once the match is shown.

const ViewScript := preload("res://scenes/main_view3d.gd")


func describe() -> Dictionary:
	return {
		"name": "The toon atlas's spare is reserved past the pages the chunk build opens",
		"description": "Art first copied into the atlas by the build of the merged chunks opens "
			+ "pages; the view then asks for the spare past those too.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.district(4)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(2)
	var view: CanvasLayer = ViewScript.new()
	t.world.add_child(view)
	view.begin(t.world.get_viewport().get_camera_2d())
	view.mirror_world(t.world)
	var side := PixelPostConfig.atlas_page
	var before := ToonAtlas.pages_used()
	# enough decals for a chunk, each needing a page of its own; the atlas first takes a decal's art
	# when the build copies it in. A row short of a page: the atlas gives a freed texture's place to
	# the next of its size, and other tests count the pages that whole-page textures open.
	for i in MirrorMergeConfig.chunk_members:
		var art := ImageTexture.create_from_image(
			Image.create(side, side - 1, false, Image.FORMAT_RGBA8)
		)
		var decal := MeshNodes.decal(Vector2(10, 10), Transform3D(), art)
		view.carrier.add_child(decal)
		view.carrier.merge.offer(decal)
	t.require(ToonAtlas.pages_used() == before, "premise: no page is opened before the build")
	view.light_world(t.world, 10, WorldGen.district_rooms(t.world.district))
	var used := ToonAtlas.pages_used()
	t.require(used > before, "premise: the build opened pages (%d to %d)" % [before, used])
	t.check(
		ToonAtlas.pages_reserved() >= used + ToonAtlas.GROW,
		"the spare is reserved past the build's pages (%d, %d used)"
			% [ToonAtlas.pages_reserved(), used],
	)
	view.queue_free()
