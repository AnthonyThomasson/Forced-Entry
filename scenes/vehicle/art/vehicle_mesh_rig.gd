class_name VehicleMeshRig
extends Node3D
## Vehicles domain, the 3D body of one car or van (built by `vehicle_mesh.gd`, carried by its twin;
## `domain-art/mesh-hook.md`): the hull is one shared mesh and the rest are parts that move, which
## `mirror_update` keeps in step with the vehicle every frame it shows. Each door leaf turns about
## its hinge (a sliding door rolls back), the front wheels steer and every wheel turns as the
## vehicle rolls, the tail lamps glow while it brakes, and a dent a bullet left shows as a dark
## patch. Nothing is rebuilt: only transforms, a glow and the patches.

const Vehicle = preload("res://scenes/vehicle/vehicle.gd")
const VehicleDoor = preload("res://scenes/vehicle/vehicle_door.gd")

## The hull's node.
var hull: MeshInstance3D
## Door id -> its part: id, node (the leaf, origin at its hinge), hinge, span (where the door shuts
## in the body: the vehicle's frame, px), and the angle and offset it was last placed at. `_parts`
## holds the same parts in the order of the vehicle's doors, so a frame walks them without a
## lookup.
var doors: Dictionary = {}
var _parts: Array[Dictionary] = []
## The wheels' pivots, each steering about the up axis, and the part of each that turns about its
## axle.
var front: Array[Node3D] = []
var wheels: Array[Node3D] = []
## Every dent patch now shown: those on the hull hang on `_dents`, those inside a door's span on
## its leaf.
var patches: Array[Node3D] = []
## The tail lamps' node (glows while braking) and whether it does now.
var tail: GeometryInstance3D
var _braking := false
## Where the wheels have turned to (rad), the steering they were last given, and their radius (px).
var _spin := 0.0
var _steer := 0.0
## Where the vehicle was at the last update (the way rolled is the distance since).
var _last_at := Vector2.INF
var radius := 15.0
## What the dents were last built from (how many, the newest one's seed) and the node the hull's
## hang on.
var _dents_count := 0
var _dents_seed := 0
var _dents := Node3D.new()


func _init() -> void:
	_dents.name = "Dents"
	add_child(_dents)


## Add a door's leaf: its `node` for door `id`, hinged at `hinge` and shut in `span` (px, the
## vehicle's frame).
func add_door(id: StringName, node: Node3D, hinge: Vector2, span: Rect2) -> void:
	var part := {
		"id": id, "node": node, "hinge": hinge, "span": span, "angle": 0.0, "offset": Vector2.ZERO,
	}
	doors[id] = part
	_parts.append(part)


## Add door `id`'s window `pane` (after `add_door`).
func add_pane(id: StringName, pane: GeometryInstance3D) -> void:
	doors[id]["pane"] = pane
	doors[id]["shown"] = 1.0


## Put every part where the 2D vehicle has it now (the mirror calls it each frame the mesh shows).
func mirror_update(body: Node2D) -> void:
	var car := body as Vehicle
	if car == null:
		return
	_doors_follow(car)
	_wheels_follow(car)
	_tail_follows(car)
	_dents_follow(car)


## Each door leaf turned about its hinge by the door's own angle, or rolled back by its offset
## (written only when the door moved).
func _doors_follow(body: Vehicle) -> void:
	var list := body.cabin.door_list()
	for i in mini(list.size(), _parts.size()):
		var door: VehicleDoor = list[i]
		var part := _parts[i]
		_pane_follows(door)
		var angle := door.angle()
		var offset := door.offset()
		if part["id"] != door.id or (part["angle"] == angle and part["offset"] == offset):
			continue
		part["angle"] = angle
		part["offset"] = offset
		var at := door.hinge + offset
		# A 2D turn clockwise on the y-down screen is `-angle` about +y.
		MeshNodes.place(part["node"], Vector3(at.x, 0.0, at.y), -angle)


## A door's window pane shown less as the door opens: whole shut, gone by the 2D glass's own fade
## (`VehicleArtConfig.glass_fade` of the opening). Written only when it changed.
func _pane_follows(door: VehicleDoor) -> void:
	var part: Dictionary = doors.get(door.id, {})
	var pane: GeometryInstance3D = part.get("pane")
	if pane == null:
		return
	var shown := 1.0 - clampf(
		door.amount() / maxf(VehicleArtConfig.glass_fade, 0.01), 0.0, 1.0
	)
	if is_equal_approx(shown, part["shown"]):
		return
	part["shown"] = shown
	MeshNodes.fade(pane, shown)
	pane.visible = shown > 0.0


## The front wheels steered by the 2D steering angle, every wheel turned by the way rolled (each
## written only when it changed).
func _wheels_follow(body: Vehicle) -> void:
	var steer: float = -body.wheel_angle()
	if steer != _steer:
		_steer = steer
		for pivot in front:
			pivot.rotation.y = steer
	if not VehicleMeshConfig.wheel_spin:
		return
	if _last_at == Vector2.INF:
		_last_at = body.global_position
	var rolled := (body.global_position - _last_at).dot(Vector2.from_angle(body.global_rotation))
	_last_at = body.global_position
	if is_zero_approx(rolled):
		return
	_spin = fmod(_spin + rolled / radius, TAU)
	for wheel in wheels:
		wheel.rotation.z = -_spin


## The tail lamps lit while the vehicle brakes (the 2D brake lights).
func _tail_follows(body: Vehicle) -> void:
	var braking: bool = body.brake_lights()
	if tail == null or braking == _braking:
		return
	_braking = braking
	MeshNodes.glow(tail, VehicleArtConfig.tail_on_color, 1.0 if braking else 0.0)


## The dark patches where bullets struck, built again only when a dent was added or dropped (the
## count and the newest seed, as the 2D drawing keys them). A patch inside a door's span hangs on
## the door's leaf, so it swings or rolls with it; the rest hang on the hull.
func _dents_follow(body: Vehicle) -> void:
	var marks: Array = body.hit_marks()
	var newest: int = marks.back()["seed"] if not marks.is_empty() else 0
	if marks.size() == _dents_count and newest == _dents_seed:
		return
	_dents_count = marks.size()
	_dents_seed = newest
	for old in patches:
		old.free()
	patches.clear()
	var heights: Dictionary = VehicleMeshConfig.heights[body.kind]
	var up := lerpf(heights["sill"], heights["belt"], VehicleMeshConfig.dent_height)
	for mark: Dictionary in marks:
		_attach(mark, up)


## Hang the patch for `mark` on the leaf of the door it struck, else on the hull.
func _attach(mark: Dictionary, up: float) -> void:
	var at: Vector2 = mark["pos"]
	var parent: Node3D = _dents
	var origin := Vector2.ZERO
	for part in _parts:
		if (part["span"] as Rect2).has_point(at):
			parent = part["node"]
			origin = part["hinge"]
			break
	var patch := _patch(mark, up, origin)
	parent.add_child(patch)
	patches.append(patch)


## The dark patch for one dent, `up` px off the ground, facing out of the body where it was struck,
## in a frame whose origin is `origin` (px, the vehicle's frame).
func _patch(mark: Dictionary, up: float, origin: Vector2) -> MeshInstance3D:
	var into: Vector2 = mark["inward"]
	var at: Vector2 = mark["pos"]
	var depth: float = mark["depth"]
	# whole pixels, so the patches share a few quads of the mesh cache however deep the dents
	var size := roundf(VehicleMeshConfig.dent_size + depth * VehicleMeshConfig.dent_growth)
	return MeshNodes.decal(
		Vector2(size, size),
		MeshNodes.surface_frame(
			Vector3(at.x - origin.x, up, at.y - origin.y), Vector3(-into.x, 0.0, -into.y)
		),
		null,
		VehicleMeshConfig.dent_color,
	)
