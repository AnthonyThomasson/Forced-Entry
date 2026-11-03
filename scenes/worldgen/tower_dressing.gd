class_name TowerDressing
## World Generation domain: what makes a district's tower read as TALL from above. Its long hard
## street shadow (`DecalFactory.shadow`), the podium band of concrete segments with pillars along
## the outside of its exterior walls, broken at every front and exit doorway (a catalogue row
## through `ObjectFactory`), and an awning and a glyph sign over its front door that fade while a
## character stands under them. Each tower is dressed from what it published (`WorldGen.get_rooms`
## and `get_openings`), so a tower turned or mirrored is dressed the way it stands.

## A run of exterior wall abuts another room when their faces are this close (px).
const ABUT := 1.0
## The sign hangs this far past the door's edge along the wall.
const SIGN_GAP := 24.0


## Dress `tower` (a `DistrictReads.get_towers` entry): returns `{ shadow, podium, awning, sign }`,
## `shadow` the sprite, `podium` the segment pieces and `awning` / `sign` the pieces over the front
## door (null when no wall run holds the sign), all children of the tower's node.
static func dress(tower: Dictionary) -> Dictionary:
	var node: Node2D = tower["node"]
	var rooms: Array = WorldGen.get_rooms(node)
	var openings: Array = WorldGen.get_openings(node)
	var half := float(HouseSpawner.plan_of(tower["plan"])["wall_thickness"]) * 0.5
	var runs := exterior_runs(rooms)
	var hangings := _hangings(node, tower["front"], runs)
	return {
		"shadow": DecalFactory.shadow(
			_local(node, (tower["rect"] as Rect2).grow(half)),
			{ "length": WorldGenTowerConfig.shadow_length },
			"Shadow",
			node,
		),
		"podium": _podium(node, runs, openings, rooms, half),
		"awning": hangings["awning"],
		"sign": hangings["sign"],
	}


## The stretches of exterior wall of `rooms` (`{ key, type, rect }`): `[{ out, line, from, to }]`,
## `out` the unit normal pointing away from the tower, `line` the wall's centreline along `out`
## (`point.dot(out)`) and `from`..`to` its stretch along the wall's axis (`point.dot(axis)`, the
## axis `Vector2(|out.y|, |out.x|)`). Each side of each room, less what another room's wall abuts.
static func exterior_runs(rooms: Array) -> Array:
	var runs: Array = []
	for room: Dictionary in rooms:
		var rect: Rect2 = room["rect"]
		for out: Vector2 in DistrictLayout.SIDES:
			var axis := _axis(out)
			var line := _face(rect, out, true)
			var abutted: Array[Vector2] = []
			for other: Dictionary in rooms:
				if other != room and absf(_face(other["rect"], out, false) - line) <= ABUT:
					abutted.append(_span(other["rect"], axis))
			for free in _free(_span(rect, axis), abutted):
				runs.append({ "out": out, "line": line, "from": free.x, "to": free.y })
	return runs


## `rect` (WORLD space) in the space of `node`.
static func _local(node: Node2D, rect: Rect2) -> Rect2:
	return Rect2(node.to_local(rect.position), rect.size)


## The unit axis along the wall a normal `out` stands on.
static func _axis(out: Vector2) -> Vector2:
	return Vector2(absf(out.y), absf(out.x))


## `rect`'s extent along `axis`, as (low, high).
static func _span(rect: Rect2, axis: Vector2) -> Vector2:
	return Vector2(rect.position.dot(axis), rect.end.dot(axis))


## The coordinate along `out` of the face of `rect` on the `out` side (`far` true) or the opposite
## side (false).
static func _face(rect: Rect2, out: Vector2, far: bool) -> float:
	var positive := out.x + out.y > 0.0
	return (rect.end if positive == far else rect.position).dot(out)


## The parts of `span` (low, high) left once the spans of `cuts` are removed, as (low, high)
## pairs at least `podium_min` long.
static func _free(span: Vector2, cuts: Array[Vector2]) -> Array[Vector2]:
	var sorted := cuts.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var pieces: Array[Vector2] = []
	var at := span.x
	for cut: Vector2 in sorted:
		pieces.append(Vector2(at, minf(cut.x, span.y)))
		at = maxf(at, cut.y)
	pieces.append(Vector2(at, span.y))
	var out: Array[Vector2] = []
	for piece in pieces:
		if piece.y - piece.x >= WorldGenTowerConfig.podium_min:
			out.append(piece)
	return out


## The podium segments round the tower's exterior walls, under a `Podium` node of `node`.
static func _podium(
	node: Node2D,
	runs: Array,
	openings: Array,
	rooms: Array,
	half: float,
) -> Array:
	var holder := Node2D.new()
	holder.name = "Podium"
	node.add_child(holder)
	var pieces: Array = []
	for run: Dictionary in runs:
		for span in _free(Vector2(run["from"], run["to"]), _door_cuts(run, openings)):
			for part in _parts(span):
				var piece := _segment(holder, run, part, rooms, half)
				if piece != null:
					pieces.append(piece)
	return pieces


## The spans of `run`'s wall a front or exit doorway on it takes: its width and the door gap each
## side.
static func _door_cuts(run: Dictionary, openings: Array) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	var out: Vector2 = run["out"]
	var axis := _axis(out)
	for door: Dictionary in openings:
		var pos: Vector2 = door["pos"]
		if not (door["front"] or door["exit"]) or absf(pos.dot(out) - float(run["line"])) > ABUT:
			continue
		var reach: float = float(door["width"]) * 0.5 + WorldGenTowerConfig.podium_door_gap
		cuts.append(Vector2(pos.dot(axis) - reach, pos.dot(axis) + reach))
	return cuts


## `span` cut into equal parts at most `podium_segment` long.
static func _parts(span: Vector2) -> Array[Vector2]:
	var count := ceili((span.y - span.x) / WorldGenTowerConfig.podium_segment)
	var step := (span.y - span.x) / float(count)
	var parts: Array[Vector2] = []
	for i in count:
		parts.append(Vector2(span.x + step * i, span.x + step * (i + 1)))
	return parts


## One podium segment over `part` of `run`, outside the wall; null where it would stand in another
## room's wall (a narrow notch).
static func _segment(
	holder: Node2D,
	run: Dictionary,
	part: Vector2,
	rooms: Array,
	half: float,
) -> Node:
	var definition := ObjectDefinitions.get_definition("podium").duplicate(true)
	var depth: float = WorldGenTowerConfig.podium_depth
	var out: Vector2 = run["out"]
	var axis := _axis(out)
	var length := part.y - part.x
	var size := axis * length + out.abs() * depth
	var centre := axis * (part.x + length * 0.5) + out * (float(run["line"]) + half + depth * 0.5)
	var area := Rect2(centre - size * 0.5, size)
	for room: Dictionary in rooms:
		if area.intersects((room["rect"] as Rect2).grow(half)):
			return null
	definition["size"] = size
	return ObjectFactory.spawn(definition, holder.to_local(centre), holder, { "facing": out })


## The awning over `front` (an opening) and the glyph sign beside it, under a `Door Dressing` node
## of `node`: `{ awning, sign }`. The sign hangs on the wall at the side of the door whose stretch
## of exterior wall (`runs`) holds it; null when neither does.
static func _hangings(node: Node2D, front: Dictionary, runs: Array) -> Dictionary:
	var holder := Node2D.new()
	holder.name = "Door Dressing"
	node.add_child(holder)
	var pos: Vector2 = front["pos"]
	var out: Vector2 = (front["outward"] as Array)[0]
	var facing := { "facing": out }
	var awning := ObjectFactory.spawn(
		ObjectDefinitions.get_definition("awning"),
		holder.to_local(pos),
		holder,
		facing,
	)
	var along := _axis(out)
	var reach := float(front["width"]) * 0.5 + SIGN_GAP
	for side: float in [reach, -reach]:
		var at: Vector2 = pos + along * side
		if _on_wall(runs, out, at):
			var sign_piece := ObjectFactory.spawn(
				ObjectDefinitions.get_definition("glyph_sign"),
				holder.to_local(at),
				holder,
				facing,
			)
			return { "awning": awning, "sign": sign_piece }
	return { "awning": awning, "sign": null }


## Whether the point `at` lies on a stretch of exterior wall facing `out`.
static func _on_wall(runs: Array, out: Vector2, at: Vector2) -> bool:
	var axis := _axis(out)
	return runs.any(
		func(r: Dictionary) -> bool:
			return (
				r["out"] == out
				and absf(at.dot(out) - float(r["line"])) <= ABUT
				and at.dot(axis) >= float(r["from"])
				and at.dot(axis) <= float(r["to"])
			),
	)
