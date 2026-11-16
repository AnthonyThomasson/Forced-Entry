class_name DistrictPrewarm
## World Generation domain: the pixel-art requests every district shares, for `WorldGen.prewarm`.
## Objects' fixed list (`SharedTextures`) plus what the tower plans fix: each footprint's shadow in
## either axis orientation and its podium segments a doorway does not cut.

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


## The requests (`PixelArt.render`'s arguments) of the district's shared art.
static func requests() -> Array:
	var footprints: Array = []
	for key: String in TowerDefinitions.get_all():
		var plan := TowerDefinitions.get_plan(key)
		footprints.append({
			"size": WorldGen.bounds(plan["rooms"]).size,
			"half": float(plan["wall_thickness"]) * 0.5,
			"length": int(WorldGenTowerConfig.shadow_length),
			"depth": WorldGenTowerConfig.podium_depth,
			"podium": TowerDressing.plan_segment_lengths(plan["rooms"]),
		})
	return SharedTextures.requests(footprints)
