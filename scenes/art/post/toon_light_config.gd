class_name ToonLightConfig
## Art domain, the pixel post (#193 phase 3, interface 27): how the toon light adds up. A
## `class_name` holder of `static var`s, read as `ToonLightConfig.<name>` (ADR 0003); `ToonMaterial`
## pushes `levels` into the toon shaders, `ToonLight` the dusk's globals.

## How strong each band of a light is, 0 to 1, darkest first, by how many bands
## (`PixelPostConfig.bands`) there are: a light's amount (N.L times its fall-off and shadow) falls
## in band `floor(amount * n)` and adds that band's strength of its colour. The darkest band is no
## light at all, so a pool and a shadow have a crisp edge, and the top one is the light whole.
static var levels_by_count: Dictionary = {
	2: [0.0, 1.0],
	3: [0.0, 0.55, 1.0],
	4: [0.0, 0.35, 0.7, 1.0],
	5: [0.0, 0.25, 0.5, 0.75, 1.0],
}
## What a surface may be lit up to (its brightest channel; the hue stays), as a multiple of its
## painted colour: the dusk's
## ambient and every light that reaches a pixel add up to this and no further (a pixel under
## several lamps is the art lit warm, not blown out). 1 is the art as painted.
static var cap: float = 1.4
## How much a positional light's N.L is made of: a face is lit by it from `1 / pool_gain` of the
## way round, so a floor stays evenly lit out to the rim of a pool hung low over it and only a face
## turned away from it falls dark.
static var pool_gain: float = 3.0


## The strengths of `count` bands (0 bands: an empty array, the shader steps nothing).
static func levels(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var row: Array = levels_by_count.get(count, [])
	for k in row.size():
		out[k] = float(row[k])
	return out
