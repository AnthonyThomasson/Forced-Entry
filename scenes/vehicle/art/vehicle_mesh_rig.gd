class_name VehicleMeshRig
extends Node3D
## Vehicles domain, the 3D body of one car or van (built by `vehicle_mesh.gd`, shown by the mirror
## in place of its proxy box; #193 phase 2, `domain-art/mesh-hook.md`): the hull is one shared mesh
## and the rest are parts that move, which `mirror_update` keeps in step with the 2D vehicle every
## frame it shows. Each door leaf turns about its hinge (a sliding door rolls back), the front
## wheels steer and every wheel turns as the vehicle rolls, the tail lamps glow while it brakes, and
## a dent a bullet left shows as a dark patch. Nothing is rebuilt: only transforms, a glow and the
## patches.

const Vehicle = preload("res://scenes/vehicle/vehicle.gd")
const VehicleDoor = preload("res://scenes/vehicle/vehicle_door.gd")

## The hull's node.
var hull: MeshInstance3D
## Door id -> { node: the leaf (origin at its hinge), angle, offset: what it was last placed at }.
var doors: Dictionary = {}
## The wheels' pivots, each steering about the up axis, and the part of each that turns about its
## axle.
var front: Array[Node3D] = []
var wheels: Array[Node3D] = []
## The tail lamps' node (glows while braking) and whether it does now.
var tail: GeometryInstance3D
var _braking := false
## Where the wheels have turned to (rad), and their radius (px).
var _spin := 0.0
## Where the vehicle was at the last update (the way rolled is the distance since).
var _last_at := Vector2.INF
var radius := 15.0
## What the dents were last built from (a hash of the dents' seeds) and the node they hang on.
var _dents_key := 0
var _dents := Node3D.new()


func _init() -> void:
	_dents.name = "Dents"
	add_child(_dents)


## Put every part where the 2D vehicle has it now (the mirror calls it each frame the mesh shows).
func mirror_update(body: Node2D) -> void:
	var car := body as Vehicle
	if car == null:
		return
	_doors_follow(car)
	_wheels_follow(car)
	_tail_follows(car)
	_dents_follow(car)


## Each door leaf turned about its hinge by the door's own angle, or rolled back by its offset.
func _doors_follow(body: Vehicle) -> void:
	for door: VehicleDoor in body.cabin.door_list():
		var part: Dictionary = doors.get(door.id, {})
		var angle := door.angle()
		var offset := door.offset()
		if part.is_empty() or (part["angle"] == angle and part["offset"] == offset):
			continue
		part["angle"] = angle
		part["offset"] = offset
		var at := door.hinge + offset
		# A 2D turn clockwise on the y-down screen is `-angle` about +y.
		MeshNodes.place(part["node"], Vector3(at.x, 0.0, at.y), -angle)


## The front wheels steered by the 2D steering angle, every wheel turned by the way rolled.
func _wheels_follow(body: Vehicle) -> void:
	var steer: float = -body.wheel_angle()
	for pivot in front:
		pivot.rotation.y = steer
	if VehicleMeshConfig.wheel_spin:
		var forward := Vector2.from_angle(body.global_rotation)
		if _last_at == Vector2.INF:
			_last_at = body.global_position
		var rolled := (body.global_position - _last_at).dot(forward)
		_last_at = body.global_position
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


## The dark patches where bullets struck, built again only when a dent was added or dropped.
func _dents_follow(body: Vehicle) -> void:
	var marks: Array = body.hit_marks()
	var key := marks.map(func(mark: Dictionary) -> int: return int(mark.get("seed", 0))).hash()
	if key == _dents_key:
		return
	_dents_key = key
	for old in _dents.get_children():
		old.free()
	var heights: Dictionary = VehicleMeshConfig.heights[body.kind]
	var up := lerpf(heights["sill"], heights["belt"], VehicleMeshConfig.dent_height)
	for mark: Dictionary in marks:
		_dents.add_child(_patch(mark, up))


## The dark patch for one dent, `up` px off the ground, facing out of the body where it was struck.
func _patch(mark: Dictionary, up: float) -> MeshInstance3D:
	var into: Vector2 = mark["inward"]
	var at: Vector2 = mark["pos"]
	var depth: float = mark["depth"]
	# whole pixels, so the patches share a few quads of the mesh cache however deep the dents
	var size := roundf(VehicleMeshConfig.dent_size + depth * VehicleMeshConfig.dent_growth)
	return MeshNodes.decal(
		Vector2(size, size),
		MeshNodes.surface_frame(Vector3(at.x, up, at.y), Vector3(-into.x, 0.0, -into.y)),
		null,
		VehicleMeshConfig.dent_color,
	)
