class_name DistrictPrewarm
## World Generation domain: the pixel-art requests every district shares, for `WorldGen.prewarm`.
## Objects' fixed list (`SharedTextures`: the street's decals) plus the flat tiles of the structure:
## every catalogue floor, the street's two tiles and the wall cap, and (`furniture_requests`) the
## furniture's.

## The Objects domain's list of pixel-art requests every district shares.
const SharedTextures = preload("res://scenes/objects/shared_textures.gd")
const ObjectArt = preload("res://scenes/objects/art/object_art.gd")


## The flat (`PixelArt.warm` with `"flat": true`) requests of every catalogued furniture piece's 3D
## art (Objects' `FurnitureArt`), so a 3D match paints none of it on the main thread: each piece
## with an art, at its size either way round (a rotated or side-facing piece is painted canonical
## at the swapped size), in its own colour and, for a wood or fabric piece, in every tone a room's
## palette gives it, and in each neon trim it can take.
static func furniture_requests() -> Array:
	var out: Array = []
	for key: String in ObjectDefinitions.keys():
		var definition := ObjectDefinitions.get_definition(key)
		var art: String = definition.get("art", "")
		if art == "":
			continue
		var size: Vector2 = definition["size"]
		var colors: Array = [definition["color"]]
		var material: String = definition.get("material", "")
		if material == "wood" or material == "fabric":
			for tone: Color in ArrangementDefinitions.palette_tones(material):
				if not colors.has(tone):
					colors.append(tone)
		var overhang: Dictionary = definition.get("overhang", {})
		var part: Vector2 = overhang.get("size", Vector2.ZERO)
		var base: Dictionary = definition.get("art_opts", {})
		for variant: Dictionary in _trims(art, base):
			var opts := base.merged(variant).merged({ "material": material })
			out.append_array(FurnitureArt.requests(
				art, [size, Vector2(size.y, size.x)], colors, opts, part
			))
	out.append_array(_podium_requests())
	out.append_array(_clutter_requests())
	out.append_array(_carried_requests())
	return out


## The option sets a piece of `art` with `base` options can come in once World Generation has
## dressed it: none, each neon trim a light-giving kind can take (`ObjectArt.neon_variants`), a
## street sign's neon (the lamps' choice) and a neon tube's tone (the dresser's).
static func _trims(art: String, base: Dictionary) -> Array:
	var out: Array = []
	for neon: String in ObjectArt.neon_variants(art, base):
		out.append({} if neon == "" else { "neon": neon })
	var colors := ["cyan", "magenta"]
	if base.get("head") == "sign":
		out.append_array(colors.map(func(name: String) -> Dictionary: return { "neon": name }))
	if base.get("kind") == "neon_tube":
		out.append_array(colors.map(func(name: String) -> Dictionary: return { "tone": name }))
	return out


## The podium segments' flat art: every length a tower plan's walls cut into, doorways included,
## `podium_depth` deep (the canonical frame whichever side it stands on).
static func _podium_requests() -> Array:
	var definition := ObjectDefinitions.get_definition("podium")
	var lengths: Array = []
	for key: String in TowerDefinitions.get_all():
		var plan := TowerDefinitions.get_plan(key)
		for length: float in TowerDressing.plan_segment_lengths(plan["rooms"], plan["openings"]):
			var size := Vector2(length, WorldGenTowerConfig.podium_depth)
			if not lengths.has(size):
				lengths.append(size)
	var opts: Dictionary = definition.get("art_opts", {}).merged(
		{ "material": definition.get("material", "") }
	)
	return FurnitureArt.requests(definition["art"], lengths, [definition["color"]], opts)


## The flat art of the items the emptied pieces carry (`PieceCarries`: a loose crate of a stack is
## 38 px across, a run of books is as wide as its books, a pallet's wrapped boxes): each row of a
## piece's `carries` and of each loose shelf at both orientations, at its own size and colour (a
## row with a `palette`: every colour of it, the one its piece's place picks).
static func _carried_requests() -> Array:
	var out: Array = []
	for key: String in ObjectDefinitions.keys():
		var definition := ObjectDefinitions.get_definition(key)
		if not PieceCarries.carries(definition):
			continue
		var size: Vector2 = definition["size"]
		var rows: Array = []
		for turned in [size, Vector2(size.y, size.x)]:
			var spec := PieceHeights.spec_of(definition)
			spec.size = turned
			rows.append_array(PieceCarries.canonical(definition, spec))
		for row: Dictionary in rows:
			var item := PieceCarries.patched(
				ObjectDefinitions.get_definition(row["key"]), PieceCarries.patch_of(row)
			)
			var opts: Dictionary = item.get("art_opts", {}).merged(
				{ "material": item.get("material", "") }
			)
			var colours: Array = [item["color"]]
			if row.has("palette"):
				colours = ObjectArtDecorConfig.prop_colors[row["palette"]]
			out.append_array(FurnitureArt.requests(
				item["art"],
				[item["size"], Vector2(item["size"].y, item["size"].x)],
				colours,
				opts,
			))
	return out


## The clutter's flat art: each kind a recipe strews, at every size `RoomDresser` can scale it to
## (even px, one factor of `clutter_scale` for both sides, either way round) and every detail
## variant `v`.
static func _clutter_requests() -> Array:
	var out: Array = []
	for key: String in ArrangementDefinitions.clutter_keys():
		var definition := ObjectDefinitions.get_definition(key)
		var art: String = definition.get("art", "")
		if art == "":
			continue
		var base: Vector2 = definition["size"]
		var sizes: Array = []
		var scale := WorldGenDressConfig.clutter_scale
		for step in 101:
			var factor := lerpf(scale.x, scale.y, step / 100.0)
			var size := ((base * factor / 2.0).round() * 2.0)
			for turned in [size, Vector2(size.y, size.x)]:
				if not sizes.has(turned):
					sizes.append(turned)
		for variant in 6:
			var opts: Dictionary = definition.get("art_opts", {}).merged({ "v": variant }, true)
			opts = opts.merged({ "material": definition.get("material", "") })
			out.append_array(FurnitureArt.requests(art, sizes, [definition["color"]], opts))
	return out


## The requests (`PixelArt.warm`'s, flat) of the district's shared art: the street's decals and the
## structure's tiles.
static func requests() -> Array:
	var out := SharedTextures.requests()
	out.append_array(structure_requests())
	return out


## The flat tile requests of the structure's 3D meshes (`StructureSkin`): each catalogue floor and
## street tile and the wall cap of each thickness a house or tower plan fixes, painted as the meshes
## ask for them. A door's leaf depends on its look and is painted when it is built.
static func structure_requests() -> Array:
	var out: Array = []
	var thicknesses := {}
	for key: String in HouseDefinitions.get_all():
		thicknesses[float(HouseDefinitions.get_plan(key)["wall_thickness"])] = true
	for key: String in TowerDefinitions.get_all():
		thicknesses[float(TowerDefinitions.get_plan(key)["wall_thickness"])] = true
	for thickness: float in thicknesses:
		_add(out, ObjectArt.flat_request(
			"wall",
			Vector2(ObjectArtWallConfig.tile_px, thickness),
			GeneralCatalog.WALL["color"],
			GeneralCatalog.WALL["art_opts"],
		))
	for key: String in GeneralCatalog.FLOORS:
		_add(out, _tile_request(GeneralCatalog.FLOORS[key]))
	for key: String in GeneralCatalog.STREET:
		_add(out, _tile_request(GeneralCatalog.STREET[key]))
	return out


## `request` onto `out`, unless it is empty (an art id Objects does not know).
static func _add(out: Array, request: Dictionary) -> void:
	if not request.is_empty():
		out.append(request)


## The flat tile request of a floor definition (`art`, `color`, `material`, `art_opts`).
static func _tile_request(definition: Dictionary) -> Dictionary:
	return ObjectArt.tile_flat_request(
		definition.get("art", "floor"),
		definition.get("color", Color(0.6, 0.5, 0.4)),
		definition.get("material", ""),
		definition.get("art_opts", {}),
	)
