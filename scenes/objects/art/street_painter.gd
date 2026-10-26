extends RefCounted
## Top-down pixel-art STREET tile painter (Objects domain, private): the street round a house, two
## seamless tiles a Floor repeats. They repeat across the whole street, so they carry only an even
## fine grain (and the sidewalk its slab joints, the one grid a sidewalk has); every mark with a
## shape (the lane dashes, odd slabs, cracks, patches, oil, gum, weeds, litter, puddles) is placed
## in the world over them instead (street_marks.gd), each its own size, turn and detail. Options
## (`art_opts`): `kind` — `asphalt` (dun, gritty asphalt) or `sidewalk` (grimy concrete slabs with
## joints). Colours and sizes: ObjectArtStreetConfig.


## The tile size (world px) of the `kind` in `opts`.
static func tile_size(opts: Dictionary) -> Vector2:
	if String(opts.get("kind", "asphalt")) == "sidewalk":
		return Vector2(ObjectArtStreetConfig.sidewalk_px, ObjectArtStreetConfig.sidewalk_px)
	return Vector2(ObjectArtStreetConfig.asphalt_px, ObjectArtStreetConfig.asphalt_px)


## Paint one tile of the `kind` in `opts`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	if String(opts.get("kind", "asphalt")) == "sidewalk":
		var base := ObjectArtStreetConfig.sidewalk_color
		c.fill(PixelShape.rounded(all, 0), base)
		c.speckle(all, base, 0.3, 0.04)
		var slab := roundi(ObjectArtStreetConfig.slab_px / ArtCanvasConfig.pixel_size)
		var joint := base.darkened(0.4)
		for k in range(0, c.w, slab):
			for i in c.h:
				c.img.set_pixel(k, i, c.at(k, i).lerp(joint, 0.9))
		for k in range(0, c.h, slab):
			for i in c.w:
				c.img.set_pixel(i, k, c.at(i, k).lerp(joint, 0.9))
		return
	var asphalt := ObjectArtStreetConfig.asphalt_color
	c.fill(PixelShape.rounded(all, 0), asphalt)
	# Even fine grain only: low contrast, no clumps, nothing to recognise.
	c.speckle(all, asphalt, 0.45, 0.05)
	c.speckle(all, asphalt, 0.1, 0.09)
