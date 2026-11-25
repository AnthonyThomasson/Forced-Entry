extends GameTest
## `TwinShapes.footprint_of` was made cheaper (#194 fixes3: the extreme points built in one array
## and moved in one product, the rings from a table): its output must be the old one's to the bit,
## since the navigation bake and the player's view read corners from it. Every shape of every
## twin of the match district (`Perf.configure_match`, seed 23, garage_home), at the pose it
## stands in and at three poses of a tilted, turned and shifted frame, is compared with
## `tests/_general/frozen_twin_shapes.gd`, the function as it was.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Frozen := preload("res://tests/_general/frozen_twin_shapes.gd")
const MIN_SHAPES := 300


func describe() -> Dictionary:
	return {
		"name": "The cheaper footprint is the old footprint, bit for bit",
		"description": "Every shape of the match district's twins, at its own pose and at turned "
			+ "and tilted ones, gives the same polygon from TwinShapes.footprint_of as from its "
			+ "frozen copy.",
		"tags": ["general", "twins", "scripted"],
		"timeout": 60.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, 2)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var poses: Array[Transform3D] = [
		Transform3D(Basis(Vector3.UP, 0.7), Vector3(13.0, 0.0, -4.5)),
		Transform3D(Basis(Vector3(1, 2, 3).normalized(), 0.9), Vector3(-7.25, 2.0, 99.0)),
		Transform3D(Basis(Vector3.BACK, PI * 0.5).scaled(Vector3(1.5, 1.0, 0.5)), Vector3.ZERO),
	]
	var seen := { "shapes": 0, "kinds": {}, "differ": 0, "first": "" }
	for body: CollisionObject3D in _bodies(t.world.get_tree().root):
		for owner_id in body.get_shape_owners():
			var at := body.global_transform * body.shape_owner_get_transform(owner_id)
			for k in body.shape_owner_get_shape_count(owner_id):
				var here: Array[Transform3D] = [at]
				here.append_array(poses)
				_compare(body.shape_owner_get_shape(owner_id, k), here, seen)
	for shape in _synthetic():
		_compare(shape, poses, seen)
	GameLog.say("footprint oracle: %d shapes, kinds %s" % [seen["shapes"], seen["kinds"].keys()])
	t.check(seen["shapes"] >= MIN_SHAPES, "premise: %d shapes" % seen["shapes"])
	t.check(seen["kinds"].size() >= 5, "premise: the kinds of shape (%s)" % [seen["kinds"].keys()])
	t.check(
		seen["differ"] == 0,
		"%d polygons differ from the frozen footprint, the first: %s" % [
			seen["differ"],
			seen["first"],
		],
	)


## Compare `shape` at each of `poses` with the frozen footprint, counting into `seen`.
func _compare(shape: Shape3D, poses: Array[Transform3D], seen: Dictionary) -> void:
	seen["kinds"][shape.get_class()] = true
	seen["shapes"] += 1
	for pose in poses:
		var live := TwinShapes.footprint_of(shape, pose)
		var old := Frozen.footprint_of(shape, pose)
		if not _same(live, old):
			seen["differ"] += 1
			if seen["first"] == "":
				seen["first"] = "%s at %s: %s vs %s" % [shape.get_class(), pose, live, old]


## The kinds the district holds none of (or one size of): a capsule, a sphere, a convex hull, a
## cylinder and a box of odd sizes.
func _synthetic() -> Array[Shape3D]:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.31
	capsule.height = 1.7
	var sphere := SphereShape3D.new()
	sphere.radius = 0.77
	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1.3, 0.2, 0), Vector3(0.4, 1.1, 0.9), Vector3(-0.6, 0.3, 1.4),
		Vector3(0.2, 0.0, -1.0)]
	)
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.123
	cylinder.height = 0.456
	var box := BoxShape3D.new()
	box.size = Vector3(0.0, 0.33, 0.71)
	var plane := WorldBoundaryShape3D.new()
	var out: Array[Shape3D] = [capsule, sphere, hull, cylinder, box, plane]
	return out


## Whether two polygons are the same points in the same order, to the bit.
func _same(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].x != b[i].x or a[i].y != b[i].y:
			return false
	return true


## Every collision body under `node`.
func _bodies(node: Node) -> Array:
	var found: Array = []
	if node is CollisionObject3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_bodies(child))
	return found
