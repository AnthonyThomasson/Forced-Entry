class_name ToonLightConfig
## Art domain, the pixel post (#193 phase 3, interface 27): how the toon light adds up. A
## `class_name` holder of `static var`s, read as `ToonLightConfig.<name>` (ADR 0003); `ToonMaterial`
## pushes `levels` into the toon shaders, `ToonLight` the dusk's globals.

## How strong each band of the sun is, 0 to 1, darkest first, by how many bands
## (`PixelPostConfig.bands`) there are: the sun's amount (N.L times its shadow) falls in band
## `floor(amount * n)` and adds that band's strength of its colour. The darkest band is no light at
## all, so a shadow has a crisp edge, and the top one is the light whole.
static var levels_by_count: Dictionary = {
	2: [0.0, 1.0],
	3: [0.0, 0.55, 1.0],
	4: [0.0, 0.35, 0.7, 1.0],
	5: [0.0, 0.25, 0.5, 0.75, 1.0],
}
## How strong each band of a positional light's pool is, darkest first (its own count: more steps
## than the sun's, so a pool reads as a few soft rings and not two or three hard ones). The
## darkest band is a little light, not none: the rim of a pool is the one hard edge left.
static var pool_levels: Array = [0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
## How much of its colour times energy a pool adds at its brightest, a multiple: 2D lights add in
## sRGB, where a light reads stronger than the same one added in the 3D render's linear light.
static var pool_strength: float = 1.4
## The ambient every surface is lit by until a world sets its own (`ToonLight.install`): a plain
## grey, so art shown with no Lighting domain is readable.
static var default_ambient: Color = Color(0.7, 0.7, 0.7)
## A fragment this many px (3D units) above the ground or more is a wall, a piece or a person
## (the room map's walls and thresholds), not the floor.
static var ground_y: float = 2.0
## What a surface may be lit up to (its brightest channel; the hue stays), as a multiple of its
## painted colour: the dusk's
## ambient and every light that reaches a pixel add up to this and no further (a pixel under
## several lamps is the art lit warm, not blown out). 1 is the art as painted.
static var cap: float = 1.7
## How much a positional light's N.L is made of: a face is lit by it from `1 / pool_gain` of the
## way round, so a floor stays evenly lit out to the rim of a pool hung low over it and only a face
## turned away from it falls dark.
static var pool_gain: float = 3.0


## The strengths of a pool's bands, the shader's eight slots padded with the last (`pool_count`
## says how many are read).
static func pool() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(8)
	if pool_levels.is_empty():
		return out
	for k in 8:
		out[k] = float(pool_levels[mini(k, pool_levels.size() - 1)]) * pool_strength
	return out


## The strengths of `count` bands (0 bands: an empty array, the shader steps nothing).
static func levels(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var row: Array = levels_by_count.get(count, [])
	for k in row.size():
		out[k] = float(row[k])
	return out
