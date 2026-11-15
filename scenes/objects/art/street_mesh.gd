extends RefCounted
## Objects domain, the 3D mesh of a piece of the street (`structure_meshes.gd`,
## `domain-art/meshes.md`;
## registered under the floor key of the `street` art): the pavement a flat slab level with a
## room's floor, a kerb band along the edges that face the road, and the road a slab
## `ObjectStreetMeshConfig.kerb` px lower with the paint laid flat on it, the lane's dashes down the
## middle and each junction's zebra bars and stop line. The wear, the glyphs and the slab joints
## are not modelled (flat paint is what reads at play zoom; the wear is the wear job's). Colours are
## the street painters' own (`ObjectArtStreetConfig`, `ObjectArtCrossingConfig`). A floor is
## static, so the mesh is built once, in a frame whose origin is the piece's corner, shared by every
## piece of one size and marks, and casts no shadow.


## The node a `floor_node` (a `Floor` of art `street`: `size`, `art_opts.kind`, `marks`) is shown
## by.
static func build(floor_node: Node2D) -> Node3D:
	var size: Vector2 = floor_node.get("size")
	var opts: Dictionary = floor_node.get("art_opts")
	var marks: Dictionary = floor_node.get("marks")
	var sidewalk := String(opts.get("kind", "asphalt")) == "sidewalk"
	var colour := ObjectArtStreetConfig.sidewalk_color if sidewalk else (
		ObjectArtStreetConfig.asphalt_color
	)
	var key_opts := _tuning()
	key_opts["sidewalk"] = sidewalk
	key_opts["lane"] = bool(marks.get("lane", false))
	key_opts["crossings"] = var_to_str(marks.get("crossings", []))
	key_opts["edges"] = var_to_str(marks.get("edges", []))
	var key := MeshCache.key("street", size, colour, key_opts)
	return MeshNodes.instance(
		MeshCache.fetch(key, func() -> Mesh: return _mesh(size, sidewalk, colour, marks)),
		Color.WHITE,
		false,
	)


## The hue of paint `paint` laid over `ground` at the paint's own opacity (the painters draw it
## translucent; a mesh face has none).
static func over(ground: Color, paint: Color, opacity: float) -> Color:
	return ground.lerp(Color(paint.r, paint.g, paint.b), opacity)


## Where the zebra bars and stop line of the junction arm at `side` (a unit vector from the road
## toward its end) of a road `size` px lie, `reach` deep, in the road's frame: the crossing
## painter's canonical layout (the junction at the bottom edge, the stop line across the left half
## at the top, a gap, the bars, a gap) turned to face `side`.
static func crossing_rects(size: Vector2, side: Vector2, reach: float) -> Array[Rect2]:
	var across := size.x if side.x == 0.0 else size.y
	var arm := _arm_rect(size, side, reach)
	var turn := side.angle() - Vector2.DOWN.angle()
	var centre := Vector2(across, reach) * 0.5
	var out: Array[Rect2] = []
	for rect in _canonical(across, reach):
		var a := arm.get_center() + (rect.position - centre).rotated(turn)
		var b := arm.get_center() + (rect.end - centre).rotated(turn)
		out.append(Rect2(a, Vector2.ZERO).expand(b))
	return out


## The stop line and the bars of a crossing arm `across` wide and `reach` deep, in the crossing
## painter's frame (`crossing_painter.gd`).
static func _canonical(across: float, reach: float) -> Array[Rect2]:
	var line := float(ObjectArtCrossingConfig.crossing_line_px)
	var gap := float(ObjectArtCrossingConfig.crossing_gap_px)
	var bar := float(ObjectArtCrossingConfig.crossing_bar_px)
	var step := float(ObjectArtCrossingConfig.crossing_step_px)
	var zone_height := maxf(1.0, reach - line - gap * 2.0)
	var out: Array[Rect2] = [Rect2(0.0, 0.0, across * 0.5, line)]
	var x := step * 0.5
	while x < across - step * 0.5:
		out.append(Rect2(x - bar * 0.5, line + gap, bar, zone_height))
		x += step
	return out


## The arm of the road whose end is at `side`, `reach` deep, over the road's whole width.
static func _arm_rect(size: Vector2, side: Vector2, reach: float) -> Rect2:
	match side:
		Vector2.DOWN:
			return Rect2(0.0, size.y - reach, size.x, reach)
		Vector2.UP:
			return Rect2(0.0, 0.0, size.x, reach)
		Vector2.RIGHT:
			return Rect2(size.x - reach, 0.0, reach, size.y)
	return Rect2(0.0, 0.0, reach, size.y)


## Every value the shape reads (and what the key adds from the piece's own marks), so a change of
## any is another mesh.
static func _tuning() -> Dictionary:
	return {
		"thickness": ObjectStructureMeshConfig.floor_thickness,
		"kerb": ObjectStreetMeshConfig.kerb,
		"lift": ObjectStreetMeshConfig.mark_lift,
		"dash": ObjectStreetMeshConfig.lane_dash,
		"gap": ObjectStreetMeshConfig.lane_gap,
		"width": ObjectStreetMeshConfig.lane_width,
		"start": ObjectStreetMeshConfig.lane_start,
		"clear": ObjectStreetMeshConfig.lane_end_clear,
		"band": ObjectStreetMeshConfig.curb_band,
		"line": ObjectStreetMeshConfig.curb_line,
		"lighten": ObjectStreetMeshConfig.curb_line_lighten,
		"curb": ObjectArtStreetConfig.curb_color.to_html(),
		"lane_paint": ObjectArtStreetConfig.lane_color.to_html(),
		"cross_paint": ObjectArtCrossingConfig.crossing_color.to_html(),
		"cross_opacity": ObjectArtCrossingConfig.crossing_opacity,
		"cross": [
			ObjectArtCrossingConfig.crossing_line_px, ObjectArtCrossingConfig.crossing_gap_px,
			ObjectArtCrossingConfig.crossing_bar_px, ObjectArtCrossingConfig.crossing_step_px,
		],
	}


## The piece's solid and paint.
static func _mesh(size: Vector2, sidewalk: bool, colour: Color, marks: Dictionary) -> Mesh:
	var kit := MeshKit.new()
	var thickness := ObjectStructureMeshConfig.floor_thickness
	var rect := Rect2(Vector2.ZERO, size)
	if sidewalk:
		# Level with the ground, deep enough that its edge shows the whole kerb over the road.
		var depth := thickness + ObjectStreetMeshConfig.kerb
		kit.box(MeshKit.volume(rect, -depth, depth), ObjectArtStreetConfig.curb_color, colour)
		_curb(kit, size, marks.get("edges", []))
		return kit.build()
	var top := -ObjectStreetMeshConfig.kerb
	kit.box(
		MeshKit.volume(rect, top - thickness, thickness),
		MeshKit.tone(colour, StringName(ObjectStructureMeshConfig.floor_edge_tone)),
		colour,
	)
	var arms: Array[Rect2] = []
	for entry: Dictionary in marks.get("crossings", []):
		var side: Vector2 = entry["side"]
		var reach: float = entry["reach"]
		arms.append(_arm_rect(size, side, reach))
		var paint := over(
			colour, ObjectArtCrossingConfig.crossing_color, ObjectArtCrossingConfig.crossing_opacity
		)
		for mark in crossing_rects(size, side, reach):
			_flat(kit, mark, top, paint)
	if marks.get("lane", false):
		_lane(kit, size, top, over(
			colour, ObjectArtStreetConfig.lane_color, ObjectArtStreetConfig.lane_color.a
		), arms)
	return kit.build()


## The lane's dashes down the middle of a road `size` px along its long side at height `top`,
## `paint` coloured, none over a junction arm in `arms`.
static func _lane(
	kit: MeshKit,
	size: Vector2,
	top: float,
	paint: Color,
	arms: Array[Rect2],
) -> void:
	var along_x := size.x >= size.y
	var length := size.x if along_x else size.y
	var middle := (size.y if along_x else size.x) * 0.5
	var width := ObjectStreetMeshConfig.lane_width
	var at := ObjectStreetMeshConfig.lane_start
	while at < length - ObjectStreetMeshConfig.lane_end_clear:
		var dash := ObjectStreetMeshConfig.lane_dash
		var rect := (
			Rect2(at, middle - width * 0.5, dash, width)
			if along_x
			else Rect2(middle - width * 0.5, at, width, dash)
		)
		var clear := true
		for arm in arms:
			clear = clear and not arm.intersects(rect)
		if clear:
			_flat(kit, rect, top, paint)
		at += dash + ObjectStreetMeshConfig.lane_gap


## The kerb on the pavement's `edges` (the sides, as unit vectors, facing the road): a dark band
## along the edge and a lighter line inside it.
static func _curb(kit: MeshKit, size: Vector2, edges: Array) -> void:
	var curb := ObjectArtStreetConfig.curb_color
	var band := ObjectStreetMeshConfig.curb_band
	var line := ObjectStreetMeshConfig.curb_line
	for side: Vector2 in edges:
		_flat(kit, _edge_band(size, side, 0.0, band), 0.0, curb)
		_flat(
			kit,
			_edge_band(size, side, band, line),
			0.0,
			curb.lightened(ObjectStreetMeshConfig.curb_line_lighten),
		)


## The band `width` px wide, `inset` px in from the `side` edge of a piece `size` px, along it.
static func _edge_band(size: Vector2, side: Vector2, inset: float, width: float) -> Rect2:
	match side:
		Vector2.UP:
			return Rect2(0.0, inset, size.x, width)
		Vector2.DOWN:
			return Rect2(0.0, size.y - inset - width, size.x, width)
		Vector2.LEFT:
			return Rect2(inset, 0.0, width, size.y)
	return Rect2(size.x - inset - width, 0.0, width, size.y)


## `rect` laid flat on the surface at height `top`, `colour` all over.
static func _flat(kit: MeshKit, rect: Rect2, top: float, colour: Color) -> void:
	kit.box(MeshKit.volume(rect, top, ObjectStreetMeshConfig.mark_lift), colour)
