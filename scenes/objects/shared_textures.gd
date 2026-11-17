extends RefCounted
## The pixel-art requests a district shares, handed to WorldGen for its boot pre-warm: the street's
## decals, a road's worn crossings and lane glyphs (`street_marks.gd`). Each request is
## `PixelArt.warm`'s flat one (`"flat": true`, with the side it faces): the exact set of arguments
## `ObjectArt.flat_facing` paints. The furniture and the structure are `DistrictPrewarm`'s.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const SIDES: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]


## Every fixed shared district decal. The glyphs are many and a district lays a few of them: they go
## last, so the sure ones are warm first.
static func requests() -> Array:
	var out: Array = []
	var glyphs: Array = []
	for side: Vector2 in SIDES:
		for v in 8:
			out.append(_request("crossing", Vector2(200, 58), side, { "v": v }))
			for number in range(7, 50):
				glyphs.append(_request("road_glyph", Vector2(80, 124), side,
					{ "text": "%02d" % number, "v": v }))
	out.append_array(glyphs)
	return out


## One complete flat `PixelArt.warm` request for an Objects painter id.
static func _request(art: String, size: Vector2, facing: Vector2, opts: Dictionary) -> Dictionary:
	var request := ObjectArt.flat_request(art, size, Color.WHITE, opts)
	request["facing"] = facing
	return request
