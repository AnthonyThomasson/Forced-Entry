extends GameTest
## Building a wall two rooms share once leaves no hole in any room's outline (#194 walls3d): walk
## every room's outline 1 px at a time, over the wall's whole thickness (both faces, out to where
## the corners and the T-junctions of the wall's neighbours reach), leaving out the doorways, and
## every step lies in at least one 2D wall shape and under at least one 3D wall. The walk covers
## houses of four plans, a district's shells with their partitions, and a layout whose rooms share a
## wall unequally (one room's side ends part way along another's: a T at the edge of a seam), so a
## piece beside a shared stretch that lost the half thickness it is lengthened by would be found.

const LayoutBuilder := preload("res://scenes/testing/layout_builder.gd")
const PLANS := ["starter_home", "open_plan_home", "corner_flat", "food_hall_tower"]
## The unequal layout: `east` is laid first and owns the stretch of `west`'s east side it covers;
## `south` shares part of `west`'s south side and ends part way along `east`'s.
const LAYOUT := {
	"thickness": 12.0,
	"doors": [],
	"rooms": [
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 300, 200) },
		{ "key": "west", "type": "bedroom", "rect": Rect2(0, 0, 400, 300) },
		{ "key": "south", "type": "bedroom", "rect": Rect2(250, 300, 450, 120) },
	],
}
## A wall's top over which a vertical ray to the ground finds a wall: start above, stop in the
## wall's last few px.
const RAY_FROM := 200.0
const RAY_TO := 90.0
## How far inside a face a walked point is (px).
const FACE_INSET := 1.0


func describe() -> Dictionary:
	return {
		"name": "Walking every room's outline finds a wall under each step, 2D and 3D",
		"description": "Houses of four plans, a district's shells and an unequally shared wall: "
			+ "each step of 1 px along each room's outline, on both faces, outside its doorways, "
			+ "is in a 2D wall shape and under a 3D wall.",
		"tags": ["worldgen", "house", "walls", "twins", "shell", "seam"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var at := Vector2(1000, 1000)
	for plan: String in PLANS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		HouseSpawner.spawn(plan, at, rng, t.world, { "street": false })
		at += Vector2(1500, 0)
	DistrictShells.build([Rect2(0, 0, 900, 700)], Vector2(0, 5000), t.world, 7)
	var layout_world := { "kind": "layout", "rooms": LAYOUT["rooms"], "doors": [] }
	layout_world["thickness"] = LAYOUT["thickness"]
	LayoutBuilder.build(layout_world, t.world).position = Vector2(0, 8000)
	await t.frames(4)
	var steps := 0
	var missing: Array = []
	for wall: Node2D in _walls(t):
		steps += _walk(t, wall, missing)
	t.check(steps > 6000, "the outlines were walked (%d steps)" % steps)
	t.check(missing.is_empty(), "%d steps have no wall: %s" % [missing.size(), missing.slice(0, 6)])


## Every wall of the world.
func _walls(t: TestContext) -> Array:
	return t.world.find_children("*", "StaticBody2D", true, false).filter(
		func(n: Node) -> bool: return n.has_method(&"wall_segments")
	)


## Walk `wall`'s outline; the steps taken; the ones with no wall in 2D or in 3D are added to
## `missing`.
func _walk(t: TestContext, wall: Node2D, missing: Array) -> int:
	var points := _outline(wall)
	for point: Vector2 in points:
		if not _walled(t, wall, point):
			missing.append("%s %v" % [wall.name, point])
	return points.size()


## The points 1 px apart along `wall`'s four sides on both faces, out past the corners to where a
## neighbour's walls reach, leaving out the doorways.
func _outline(wall: Node2D) -> Array[Vector2]:
	var thick: float = wall.get("wall_thickness")
	var rect := Rect2(wall.global_position, wall.get("size"))
	var out: Array[Vector2] = []
	for horizontal in [true, false]:
		for near in [true, false]:
			var side := _side(horizontal, near)
			var length := rect.size.x if horizontal else rect.size.y
			var line := rect.position.y if horizontal else rect.position.x
			if not near:
				line += rect.size.y if horizontal else rect.size.x
			var s := -thick * 0.5 + 0.5
			while s < length + thick * 0.5:
				if not _in_doorway(wall, side, s):
					out.append_array(_faces(rect, horizontal, s, line, thick))
				s += 1.0
	return out


## The two points `s` px along the wall on `line` (the wall's centre line), one on each face.
func _faces(rect: Rect2, horizontal: bool, s: float, line: float, thick: float) -> Array[Vector2]:
	var along := (rect.position.x if horizontal else rect.position.y) + s
	var inset := thick * 0.5 - FACE_INSET
	var made: Array[Vector2] = []
	for face: float in [-1.0, 1.0]:
		var across := line + face * inset
		made.append(Vector2(along, across) if horizontal else Vector2(across, along))
	return made


## The `Wall.Side` of the top/bottom (`horizontal`) or left/right wall, the near or far one.
func _side(horizontal: bool, near: bool) -> int:
	if horizontal:
		return WallFactory.WallScript.Side.TOP if near else WallFactory.WallScript.Side.BOTTOM
	return WallFactory.WallScript.Side.LEFT if near else WallFactory.WallScript.Side.RIGHT


## Whether `s` px along `wall`'s `side` is in one of its doorways.
func _in_doorway(wall: Node2D, side: int, s: float) -> bool:
	for gap: Dictionary in wall.get("openings"):
		if gap["side"] == side and absf(s - float(gap["offset"])) <= float(gap["width"]) * 0.5:
			return true
	return false


## Whether `point` (plan px) is in a 2D wall shape and under a 3D wall.
func _walled(t: TestContext, wall: Node2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collide_with_areas = false
	var in2d := false
	for found: Dictionary in wall.get_world_2d().direct_space_state.intersect_point(query, 16):
		in2d = in2d or (found["collider"] as Object).has_method(&"wall_segments")
	var ray := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(point, RAY_FROM), PlanSpace.lift(point, RAY_TO), PhysicsLayers.TWIN_WORLD
	)
	var hit := TwinSpace.space_of(t.world).intersect_ray(ray)
	var owner := TwinSpace.owner_of(hit["collider"]) if not hit.is_empty() else null
	return in2d and owner != null and owner.has_method(&"wall_segments")
