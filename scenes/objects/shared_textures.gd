extends RefCounted
## The pixel-art requests a district shares, handed to WorldGen for its boot pre-warm. Each request
## is PixelArt.render's complete argument set: `{ painter, size, color, facing, opts }`. These art
## ids all take their colours as given, so the requests are exactly what ObjectArt.texture renders.
## Tower footprints let the same list cover every plan's shadow in either axis orientation.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const SIDES: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
const SHELLS := {
	"rebar": { "size": Vector2(104, 20), "material": "metal" },
	"rubble": { "size": Vector2(70, 48), "material": "stone" },
	"scaffold": { "size": Vector2(120, 52), "material": "metal" },
	"cement": { "size": Vector2(88, 40), "material": "plastic" },
	"stain": { "size": Vector2(72, 46), "material": "stone" },
}


## Every fixed shared district texture, plus, for each `{ size, half, length, depth, podium }` tower
## footprint, its shadow and the podium segments of `podium` lengths (px) it can stand with.
static func requests(tower_footprints: Array = []) -> Array:
	var out: Array = []
	# Glyphs are many and a district draws a few of them: they go last, so the sure ones are warm
	# first.
	var glyphs: Array = []
	for side: Vector2 in SIDES:
		for v in 8:
			out.append(_request("crossing", Vector2(200, 58), Color.WHITE, side, { "v": v }))
			for number in range(7, 50):
				glyphs.append(_request("road_glyph", Vector2(80, 124), Color.WHITE, side,
					{ "text": "%02d" % number, "v": v }))
		# A piece's size is as it stands: its canonical size turned for a side-facing one.
		var horizontal := absf(side.x) > 0.0
		out.append(_request("awning", _stood(Vector2(120, 36), horizontal), Color(0.1, 0.34, 0.36),
			side, { "kind": "awning", "part": "overhang", "material": "metal" }))
		out.append(_request("awning", _stood(Vector2(26, 72), horizontal), Color(0.09, 0.09, 0.12),
			side, { "kind": "hanging", "part": "overhang", "material": "metal" }))
		for kind: String in SHELLS:
			var shell: Dictionary = SHELLS[kind]
			# Scattered decor is turned either way on any side; a stain runs down a north or south
			# wall only, as drawn.
			for rotated in [false, true]:
				if kind == "stain" and (rotated or horizontal):
					continue
				out.append(_request("shell_decor", _stood(shell["size"], rotated),
					Color(0.5, 0.5, 0.52), side, { "kind": kind, "material": shell["material"] }))
	for footprint: Dictionary in tower_footprints:
		_podium(out, footprint)
		_shadow(out, footprint)
		var turned := footprint.duplicate()
		turned["size"] = Vector2(footprint["size"].y, footprint["size"].x)
		_shadow(out, turned)
	out.append_array(glyphs)
	return out


## `size` as a piece facing a side of the screen stands: turned a quarter when it faces left or
## right.
static func _stood(size: Vector2, horizontal: bool) -> Vector2:
	return Vector2(size.y, size.x) if horizontal else size


## One complete PixelArt request for an Objects painter id.
static func _request(art: String, size: Vector2, color: Color, facing: Vector2,
		opts: Dictionary) -> Dictionary:
	var options := opts.duplicate()
	options["material"] = opts.get("material", "")
	return {
		"painter": ObjectArt.PAINTERS[art],
		"size": size,
		"color": color,
		"facing": facing,
		"opts": options,
	}


## Add the exact shadow DecalFactory paints for one tower footprint.
static func _shadow(out: Array, footprint: Dictionary) -> void:
	var half := float(footprint["half"])
	var foot_size: Vector2 = footprint["size"] + Vector2.ONE * half * 2.0
	var foot := Rect2(-Vector2.ONE * half, foot_size)
	var length := int(footprint["length"])
	var drag := (-ArtCanvasConfig.light_from.normalized() * float(length)).round()
	var area := foot.merge(Rect2(foot.position + drag, foot.size))
	out.append(_request("shadow", area.size, Color.WHITE, Vector2.DOWN, {
		"foot": Rect2i(Rect2(foot.position - area.position, foot.size)),
		"length": length,
	}))


## The podium segments of a footprint's `podium` lengths (`depth` px deep), on every side of a
## tower.
static func _podium(out: Array, footprint: Dictionary) -> void:
	var depth := float(footprint.get("depth", 20.0))
	for length: float in footprint.get("podium", []):
		for side: Vector2 in SIDES:
			var size := Vector2(depth, length) if absf(side.x) > 0.0 else Vector2(length, depth)
			out.append(_request("podium", size, Color(0.47, 0.46, 0.42), side,
				{ "material": "stone" }))
