class_name DistrictPrewarm
## World Generation domain: the pixel-art requests every district shares, for `WorldGen.prewarm`.
## Objects' fixed list (`SharedTextures`) plus what the tower plans fix: each footprint's shadow in
## either axis orientation and its podium segments a doorway does not cut.

## The Objects domain's list of pixel-art requests every district shares.
const SharedTextures = preload("res://scenes/objects/shared_textures.gd")


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
