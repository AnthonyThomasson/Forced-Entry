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
		for neon in ObjectArt.neon_variants(art, base):
			var opts := base if neon == "" else base.merged({ "neon": neon })
			opts = opts.merged({ "material": material })
			out.append_array(FurnitureArt.requests(
				art, [size, Vector2(size.y, size.x)], colors, opts, part
			))
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
