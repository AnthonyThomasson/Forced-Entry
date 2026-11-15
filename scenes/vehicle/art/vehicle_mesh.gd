extends RefCounted
## Vehicles domain, the 3D mesh of a car or a van (#193 phase 2, `domain-art/meshes.md`): a low-poly
## hull at the kind's footprint with its door spans cut out, a cabin of glass under a roof slab with
## a sloped windscreen and rear window, a leaf for each door that opens with the 2D door's state,
## wheels on their sides that steer and turn, head and tail lamps, bumpers and wing mirrors. Every
## measure is the kind's `VehicleConfig` row and `looks` (the painters' own), the heights
## `VehicleMeshConfig`; Art's kit does the rest, in px. The hull and each door leaf carry the 2D
## art (#193 phase 2b, `VehicleSkin`: the car and van painters' flat paint of the vehicle's `color`
## projected straight down, white vertex colours so the art shows as painted), so a car seen from
## above reads as the 2D car does; the wheels and the tail lamps keep the kit's own colours. The
## hull, each door, the wheel and the tail lamps are `MeshCache` meshes shared by every vehicle of
## the kind (the paint is in the texture, one per kind and paint); `VehicleMeshRig` (the node
## returned) moves them. Dents are patches on the rig, not a rebuilt hull, so the cache stays
## bounded however many hits there are.

const Vehicle = preload("res://scenes/vehicle/vehicle.gd")
const Art = preload("res://scenes/vehicle/art/vehicle_art.gd")
const Rig = preload("res://scenes/vehicle/art/vehicle_mesh_rig.gd")


## The node vehicle `body` (a `vehicle.gd`) is shown by, in 3D units with its origin at the body's
## (x forward, y to its right, as every door, axle and lamp of the row is), or null for a kind with
## no row in `VehicleConfig` or `VehicleMeshConfig.heights`.
static func build(body: Node2D) -> Node3D:
	var car := body as Vehicle
	if (
		car == null
		or not VehicleConfig.kinds.has(car.kind)
		or not VehicleMeshConfig.heights.has(car.kind)
	):
		return null
	var row: Dictionary = car.row()
	var look: Dictionary = VehicleConfig.looks[car.kind]
	var tuning := _tuning(car.kind, row, look)
	var rig := Rig.new()
	_add_hull(rig, car, tuning)
	for def: Dictionary in row["doors"]:
		_add_door(rig, car, def, tuning)
	_add_wheels(rig, row, tuning)
	var tail_key := MeshCache.key("vehicle_tail", row["size"], Color.WHITE, tuning)
	rig.tail = MeshNodes.instance(MeshCache.fetch(
		tail_key, func() -> Mesh: return tail_lamps(car.kind, row, look)
	))
	rig.tail.name = "Tail"
	MeshNodes.glow(rig.tail, VehicleArtConfig.tail_on_color, 0.0)
	rig.add_child(rig.tail)
	return rig


## The hull on `rig`: one cached mesh per kind, textured with the body's 2D art in its paint.
static func _add_hull(rig: Rig, car: Vehicle, tuning: Dictionary) -> void:
	var row: Dictionary = car.row()
	var look: Dictionary = VehicleConfig.looks[car.kind]
	var key := MeshCache.key("vehicle_hull", row["size"], Color.WHITE, tuning)
	var skin := VehicleSkin.body(car.kind, car.color)
	rig.hull = MeshNodes.textured(
		MeshCache.fetch(key, func() -> Mesh: return hull(car.kind, row, look, car.outline())),
		skin["texture"],
		skin["rect"],
	) as MeshInstance3D
	rig.hull.name = "Hull"
	rig.add_child(rig.hull)


## The leaf of door `def` on `rig`, at its hinge, textured with the door panel's 2D art.
static func _add_door(rig: Rig, car: Vehicle, def: Dictionary, tuning: Dictionary) -> void:
	var row: Dictionary = car.row()
	var look: Dictionary = VehicleConfig.looks[car.kind]
	var key := MeshCache.key("vehicle_door:%s" % def["id"], row["size"], Color.WHITE, tuning)
	var skin := VehicleSkin.door(car.kind, def, car.color)
	var leaf := MeshNodes.textured(
		MeshCache.fetch(key, func() -> Mesh: return door(car.kind, look, def, car.outline())),
		skin["texture"],
		skin["rect"],
	) as MeshInstance3D
	leaf.name = "Door_%s" % def["id"]
	var hinge: Vector2 = def["hinge"]
	MeshNodes.place(leaf, Vector3(hinge.x, 0.0, hinge.y))
	rig.add_child(leaf)
	rig.add_door(def["id"], leaf, hinge, _span(def, look["door_depth"], true))


## The hull: the body's outline cut at every door's span, from the sill to the belt, with the dark
## recess behind each cut, the bumpers and head lamps, and the cabin over it. Every face is white:
## the art is the texture's (`VehicleSkin.body`), the shape only the mesh's.
static func hull(kind: StringName, row: Dictionary, look: Dictionary,
		outline: PackedVector2Array) -> Mesh:
	var heights: Dictionary = VehicleMeshConfig.heights[kind]
	var sill: float = heights["sill"]
	var belt: float = heights["belt"]
	var kit := MeshKit.new()
	var shape := outline
	var depth: float = look["door_depth"]
	for def: Dictionary in row["doors"]:
		shape = _cut(shape, _span(def, depth, true))
	kit.extrude(shape, sill, belt - sill, Color.WHITE)
	for def: Dictionary in row["doors"]:
		var span := _span(def, depth, false)
		var inner := _inner_wall(span, _outward(def))
		kit.box(MeshKit.volume(span, sill, 2.0), Color.WHITE)
		kit.box(MeshKit.volume(inner, sill + 2.0, belt - sill - 2.0), Color.WHITE)
	_bumpers(kit, row, look, sill)
	_head_lamps(kit, kind, row, look)
	_cabin(kit, kind, look)
	return kit.build()


## One door's leaf, at the shut pose and in the frame of its hinge (the rig places it there and
## turns it): a slab from the sill to the belt that fits its notch with a seam, and a wing mirror on
## the doors that carry one. White, as the hull is: the panel's art is `VehicleSkin.door`.
static func door(kind: StringName, look: Dictionary, def: Dictionary,
		outline: PackedVector2Array) -> Mesh:
	var heights: Dictionary = VehicleMeshConfig.heights[kind]
	var sill: float = heights["sill"]
	var belt: float = heights["belt"]
	var hinge: Vector2 = def["hinge"]
	var kit := MeshKit.new()
	kit.pose(Transform3D(Basis.IDENTITY, Vector3(-hinge.x, 0.0, -hinge.y)))
	var leaf := _span(def, look["door_depth"], true)
	leaf = _along_shrunk(leaf, def, VehicleMeshConfig.door_gap)
	var shape := _largest(Geometry2D.intersect_polygons(_ring(leaf), outline))
	if shape.size() < 3:
		push_warning("VehicleMesh: door '%s' lies outside the %s's outline" % [def["id"], kind])
	kit.extrude(shape, sill, belt - sill, Color.WHITE)
	if def["kind"] != &"rear" and (look["mirror"] as Array).has(def["id"]):
		_mirror(kit, def, belt)
	return kit.build()


## One wheel, its axle along the vehicle's y and centred on the origin: a tyre, a hub a little wider
## than it and a spoke across each hub's face, so the turning shows.
static func wheel(row: Dictionary) -> Mesh:
	var size: Vector2 = row["wheel_size"]
	var radius := size.x * 0.5
	var half := size.y * 0.5
	var proud := VehicleMeshConfig.proud
	var kit := MeshKit.new()
	# the cylinder stands up: turn it onto its side (up becomes the axle, along z)
	kit.pose(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	kit.cylinder(Vector3(0.0, -half, 0.0), radius, size.y, VehicleArtConfig.tyre_color)
	kit.cylinder(Vector3(0.0, -half - proud, 0.0), radius * VehicleMeshConfig.hub_ratio,
		size.y + 2.0 * proud, VehicleArtConfig.hub_color)
	kit.pose(Transform3D.IDENTITY)
	var spoke := VehicleMeshConfig.spoke
	var reach := radius * VehicleMeshConfig.hub_ratio
	for side in [-1.0, 1.0]:
		var z: float = half + proud if side > 0.0 else -(half + 2.0 * proud)
		kit.box(
			AABB(Vector3(-reach, -spoke * 0.5, z), Vector3(reach * 2.0, spoke, proud)),
			VehicleArtConfig.tyre_color,
		)
	return kit.build()


## Both tail lamps in one mesh (so one glow lights both): the unlit colour, at the tail's corners.
static func tail_lamps(kind: StringName, row: Dictionary, look: Dictionary) -> Mesh:
	var heights: Dictionary = VehicleMeshConfig.heights[kind]
	var lamp: Vector2 = heights["lamp"]
	var kit := MeshKit.new()
	for rect: Rect2 in Art.tail_lamps(row, look):
		var proud := Vector2(VehicleMeshConfig.proud, 0.0)
		var lit := Rect2(rect.position - proud, rect.size + proud)
		kit.box(MeshKit.volume(lit, lamp.x, lamp.y - lamp.x), VehicleArtConfig.tail_off_color)
	return kit.build()


## The four wheels at the axles as the 2D draws them, the front pair on pivots that steer.
static func _add_wheels(rig: Rig, row: Dictionary, tuning: Dictionary) -> void:
	var size: Vector2 = row["wheel_size"]
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	rig.radius = size.x * 0.5
	var key := MeshCache.key("vehicle_wheel", size, Color.WHITE, tuning)
	var mesh := MeshCache.fetch(key, func() -> Mesh: return wheel(row))
	for x: float in [row["axle_front"], row["axle_rear"]]:
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.name = "Wheel_%s_%s" % [
				"front" if x == row["axle_front"] else "rear",
				"right" if side > 0.0 else "left",
			]
			MeshNodes.place(pivot, Vector3(x, size.x * 0.5, side * (half.y - size.y * 0.35)))
			var tyre := MeshNodes.instance(mesh)
			pivot.add_child(tyre)
			rig.add_child(pivot)
			rig.wheels.append(tyre)
			if x == row["axle_front"]:
				rig.front.append(pivot)


## The bumpers: black bars across the nose and the tail between the corners.
static func _bumpers(kit: MeshKit, row: Dictionary, look: Dictionary, sill: float) -> void:
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	var across := half.y - float(row["corner"])
	var depth: float = look["bumper"]
	var proud := VehicleMeshConfig.proud
	for end in [-1.0, 1.0]:
		var near: float = end * (half.x - depth)
		var far: float = end * (half.x + proud)
		var rect := Rect2(
			Vector2(minf(near, far), -across),
			Vector2(absf(far - near), 2.0 * across),
		)
		kit.box(MeshKit.volume(rect, sill, VehicleMeshConfig.bumper_height), Color.WHITE)


## The head lamps at the nose's corners.
static func _head_lamps(kit: MeshKit, kind: StringName, row: Dictionary, look: Dictionary) -> void:
	var heights: Dictionary = VehicleMeshConfig.heights[kind]
	var lamp: Vector2 = heights["lamp"]
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	var span: Vector2 = look["head"]
	var length: float = look["lamp"]
	for side in [-1.0, 1.0]:
		var y0: float = minf(side * span.x, side * span.y)
		var rect := Rect2(
			Vector2(half.x - length, y0),
			Vector2(length + VehicleMeshConfig.proud, absf(span.y - span.x)),
		)
		kit.box(MeshKit.volume(rect, lamp.x, lamp.y - lamp.x), Color.WHITE)


## The cabin over the belt: a roof slab on the roof's span, the dark glass under it (the doors'
## windows) between the pillars, a sloped windscreen in front and rear window behind. A van's
## cargo behind its cab windows is one solid block.
static func _cabin(kit: MeshKit, kind: StringName, look: Dictionary) -> void:
	var heights: Dictionary = VehicleMeshConfig.heights[kind]
	var belt: float = heights["belt"]
	var roof: float = heights["roof"]
	var front: float = (look["roof"] as Vector2).x
	var back: float = (look["roof"] as Vector2).y
	var half: float = look["roof_half"]
	var band_back := _band_back(look)
	var slab := VehicleMeshConfig.roof_thickness
	if band_back > back:
		var block := Rect2(back, -half, band_back - back, 2.0 * half)
		kit.box(MeshKit.volume(block, belt, roof - belt), Color.WHITE)
	var band := Rect2(band_back, -half, front - band_back, 2.0 * half)
	kit.box(MeshKit.volume(band, belt, roof - belt - slab), Color.WHITE)
	kit.box(MeshKit.volume(band, roof - slab, slab), Color.WHITE)
	_pillars(kit, look, belt, roof)
	_screens(kit, look, belt, roof)


## Where the glass band of the cabin starts (x): the back of the doors' windows, or the roof's back
## when they reach it (a car), so a van's cargo behind its cab is a block.
static func _band_back(look: Dictionary) -> float:
	var back: float = (look["roof"] as Vector2).y
	var glass_back: float = (look["roof"] as Vector2).x
	for span: Vector2 in (look["glass"] as Dictionary).values():
		glass_back = minf(glass_back, span.x)
	var start := maxf(back, glass_back)
	return back if start - back < 4.0 else start


## The fixed pillars between the door windows, as wide as the roof (a little more).
static func _pillars(kit: MeshKit, look: Dictionary, belt: float, roof: float) -> void:
	var wide: float = float(look["roof_half"]) + VehicleMeshConfig.proud
	for pillar: Vector2 in look["pillars"]:
		var from := maxf(pillar.x, _band_back(look))
		var to := minf(pillar.y, (look["roof"] as Vector2).x)
		if to > from:
			var post := Rect2(from, -wide, to - from, 2.0 * wide)
			kit.box(MeshKit.volume(post, belt, roof - belt), Color.WHITE)


## The sloped windscreen from the roof's front to the bonnet, and the rear window from the roof's
## back to the boot (a van has none).
static func _screens(kit: MeshKit, look: Dictionary, belt: float, roof: float) -> void:
	var half: float = look["roof_half"]
	var front: float = (look["roof"] as Vector2).x
	var back: float = (look["roof"] as Vector2).y
	var screen := Rect2(front, -half, float(look["bonnet"]) - front, 2.0 * half)
	kit.wedge(MeshKit.volume(screen, belt, roof - belt), Vector2.LEFT, Color.WHITE)
	var boot: float = look["boot"]
	if float(look["rear_half"]) > 0.0 and boot < back:
		var rear := Rect2(boot, -half, back - boot, 2.0 * half)
		kit.wedge(MeshKit.volume(rear, belt, roof - belt), Vector2.RIGHT, Color.WHITE)


## The wing mirror on a front door: out from the door's skin near its hinge, just over the belt.
static func _mirror(kit: MeshKit, def: Dictionary, belt: float) -> void:
	var hinge: Vector2 = def["hinge"]
	var handle: Vector2 = def["handle"]
	var size := VehicleMeshConfig.mirror_size
	var along := signf(handle.x - hinge.x)
	var out := _outward(def)
	var x0 := hinge.x + along * VehicleMeshConfig.mirror_from
	var x1 := x0 + along * size.y
	var y0 := hinge.y
	var y1 := hinge.y + out.y * size.x
	var rect := Rect2(Vector2(minf(x0, x1), minf(y0, y1)), Vector2(absf(x1 - x0), absf(y1 - y0)))
	kit.box(MeshKit.volume(rect, belt + VehicleMeshConfig.mirror_lift, size.z), Color.WHITE)


## Out of the body through `def`'s door (unit): a rear door out of the tail, the others the side.
static func _outward(def: Dictionary) -> Vector2:
	if def["kind"] == &"rear":
		return Vector2.LEFT
	return Vector2(0.0, signf((def["handle"] as Vector2).y))


## The footprint of door `def` (the vehicle's frame): along the body between its hinge and its
## handle (a sliding door: its length back from the hinge) and `depth` deep into the body from its
## skin. `cut` stands the outer edge 4 px beyond the skin so a cut through the hull leaves a clean
## notch.
static func _span(def: Dictionary, depth: float, cut: bool) -> Rect2:
	var hinge: Vector2 = def["hinge"]
	var handle: Vector2 = def["handle"]
	var out := _outward(def)
	var reach := 4.0 if cut else 0.0
	if def["kind"] == &"rear":
		var y0 := minf(hinge.y, handle.y)
		return Rect2(hinge.x - reach, y0, depth + reach, absf(hinge.y - handle.y))
	var length: float = def.get("length", hinge.distance_to(handle))
	var x0 := minf(hinge.x, handle.x) if def["kind"] != &"slide" else hinge.x - length
	var span_x := absf(hinge.x - handle.x) if def["kind"] != &"slide" else length
	var inner := hinge.y - out.y * depth
	var outer := hinge.y + out.y * reach
	return Rect2(Vector2(x0, minf(inner, outer)), Vector2(span_x, absf(outer - inner)))


## `rect` shortened by `gap` at both ends along the door (its length, not its depth).
static func _along_shrunk(rect: Rect2, def: Dictionary, gap: float) -> Rect2:
	if def["kind"] == &"rear":
		return rect.grow_individual(0.0, -gap, 0.0, -gap)
	return rect.grow_individual(-gap, 0.0, -gap, 0.0)


## The thin wall standing proud of a notch's inner face (what the recess shows when the door is
## open).
static func _inner_wall(span: Rect2, out: Vector2) -> Rect2:
	var thick := VehicleMeshConfig.proud
	if out.x != 0.0:
		return Rect2(span.end.x - thick, span.position.y, thick, span.size.y)
	if out.y > 0.0:
		return Rect2(span.position.x, span.position.y, span.size.x, thick)
	return Rect2(span.position.x, span.end.y - thick, span.size.x, thick)


## `shape` with `rect` cut out of it (the biggest piece that is left).
static func _cut(shape: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var left := Geometry2D.clip_polygons(shape, _ring(rect))
	return _largest(left) if not left.is_empty() else shape


## The biggest polygon of `pieces` (an empty one when none).
static func _largest(pieces: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for piece in pieces:
		var area := _area(piece)
		if area > best_area:
			best_area = area
			best = piece
	return best


## A polygon's area (the shoelace sum, unsigned).
static func _area(polygon: PackedVector2Array) -> float:
	var twice := 0.0
	for i in polygon.size():
		twice += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(twice) * 0.5


## `rect`'s four corners as a polygon.
static func _ring(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


## Every value the shapes read, so a retuned holder is another mesh: the kind's rows (as text), the
## mesh holder's numbers, and the colours the wheels and tail lamps (the kit's own) take.
static func _tuning(kind: StringName, row: Dictionary, look: Dictionary) -> Dictionary:
	return {
		"kind": String(kind), "row": str(row), "look": str(look),
		"heights": str(VehicleMeshConfig.heights[kind]),
		"mesh": [
			VehicleMeshConfig.roof_thickness, VehicleMeshConfig.door_gap, VehicleMeshConfig.proud,
			VehicleMeshConfig.bumper_height, VehicleMeshConfig.hub_ratio, VehicleMeshConfig.spoke,
			str(VehicleMeshConfig.mirror_size), VehicleMeshConfig.mirror_from,
			VehicleMeshConfig.mirror_lift,
		],
		"art": [
			str(VehicleArtConfig.tyre_color), str(VehicleArtConfig.hub_color),
			str(VehicleArtConfig.tail_off_color),
		],
	}
