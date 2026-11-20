extends GameTest
## A wall two rooms share is built once (#194 walls3d): where two rooms' outlines run along the
## same line, the room built first owns the stretch they share and the other builds no collider
## there (it keeps the stretch as a segment, so its doorways stay cut where they
## are). So every wall segment of a house, and of a district shell with its partitions, has exactly
## one collider: a ray through the middle of a segment meets one 3D wall, and two segments that lie
## on one another are never both built.

const FAR_APART := Vector2(1500, 0)
const PLANS := ["starter_home", "open_plan_home", "corner_flat", "food_hall_tower"]
const SEEDS := [1, 2]
## Segments overlap if they run along one another for more than this (px).
const OVERLAP := 1.0
## A sample point lies this far (px, a wall's thickness times it) from a wall that ends on its
## own: a corner or a T is where two walls rightly overlap.
const JUNCTION := 1.5
const RAY_HEIGHT := 48.0
## A level ray low in a doorway, and one over its door leaf's height (84) under the wall's top (96).
const DOOR_LOW := 60.0
const LINTEL_RAY := 90.0

## Height (px) of the level rays: inside every wall, under every lintel.
var _doorways_checked := 0


func describe() -> Dictionary:
	return {
		"name": "A wall two rooms share is built once",
		"description": "For houses of several plans and a district's shells: no two built wall "
			+ "segments lie on one another, and the middle of each segment is met by exactly one "
			+ "3D wall twin.",
		"tags": ["worldgen", "house", "walls", "twins", "shell"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var at := Vector2(1000, 1000)
	var holders: Array[Node2D] = []
	for plan: String in PLANS:
		for house_seed: int in SEEDS:
			var rng := RandomNumberGenerator.new()
			rng.seed = house_seed
			var house := HouseSpawner.spawn(plan, at, rng, t.world, { "street": false })
			house.name = "%s %d" % [plan, house_seed]
			holders.append(house)
			at += FAR_APART
	var shells := DistrictShells.build(
		[Rect2(0, 0, 900, 700), Rect2(1100, 0, 800, 900)],
		Vector2(0, 5000),
		t.world,
		7,
	)
	for shell: Dictionary in shells:
		holders.append(shell["holder"])
	await t.frames(4)
	var checked := 0
	for holder in holders:
		checked += _check(t, holder)
	t.check(_doorways_checked >= 10, "doorways were checked (%d)" % _doorways_checked)
	t.check(checked >= 40, "the houses and shells have shared and plain segments (%d)" % checked)


## The checks for the walls under `holder`; how many segment middles were sampled.
func _check(t: TestContext, holder: Node2D) -> int:
	var walls: Array[Node2D] = []
	for child in holder.get_children():
		if child.has_method(&"wall_segments"):
			walls.append(child)
	var rows: Array = []  # { wall, index, a, b, built }
	for wall in walls:
		var built: Dictionary = wall.segment_shapes()
		var segs: Array = wall.wall_segments()
		for i in segs.size():
			var seg: PackedVector2Array = segs[i]
			if seg[0].is_equal_approx(seg[1]):
				continue
			rows.append({
				"wall": wall,
				"index": i,
				"a": wall.global_position + seg[0],
				"b": wall.global_position + seg[1],
				"built": built.has(i),
			})
	_no_stacked_pair(t, holder, rows)
	var sampled := 0
	for row: Dictionary in rows:
		if row["built"] and _sample(t, holder, row, rows):
			sampled += 1
	_doorways(t, holder, rows)
	return sampled


## Every doorway of `holder` is open under its lintel and has the one lintel over it, whichever
## room owns the wall it is cut in: a level ray through its middle meets no wall low and one high.
func _doorways(t: TestContext, holder: Node2D, rows: Array) -> void:
	for opening: Dictionary in WorldGen.get_openings(holder):
		var pos: Vector2 = opening["pos"]
		var half: float = opening["width"] * 0.5
		var along := Vector2.ZERO
		for row: Dictionary in rows:
			for end: Vector2 in [row["a"], row["b"]]:
				if absf(end.distance_to(pos) - half) < 1.5:
					along = ((row["b"] as Vector2) - (row["a"] as Vector2)).normalized()
		if along == Vector2.ZERO:
			continue
		_doorways_checked += 1
		var across := along.orthogonal() * 12.0
		var label := "%s: the doorway at %s" % [holder.name, pos]
		t.check(
			_walls_along(t, pos + across, pos - across, DOOR_LOW) == 0,
			"%s is open under its lintel" % label,
		)
		var lintels := _walls_along(t, pos + across, pos - across, LINTEL_RAY)
		t.check(lintels == 1, "%s has one lintel over it, not %d" % [label, lintels])


## No two segments that run along one another are both built; each unbuilt one has a built one on
## it.
func _no_stacked_pair(t: TestContext, holder: Node2D, rows: Array) -> void:
	for i in rows.size():
		var covered: bool = not rows[i]["built"]
		var seen := false
		for j in rows.size():
			if i == j or _run_along(rows[i], rows[j]) <= OVERLAP:
				continue
			if rows[i]["built"] and rows[j]["built"] and i < j:
				t.check(false, "%s: segments %s and %s are both built on one another" % [
					holder.name, _label(rows[i]), _label(rows[j])])
			if rows[j]["built"]:
				seen = true
		if covered:
			t.check(seen, "%s: the unbuilt segment %s has no built one on it" % [
				holder.name, _label(rows[i])])


## `row`'s middle: one 3D wall twin meets it (false: no sample, too near a junction or too short).
func _sample(t: TestContext, holder: Node2D, row: Dictionary, rows: Array) -> bool:
	var a: Vector2 = row["a"]
	var b: Vector2 = row["b"]
	var thick: float = (row["wall"] as Node2D).get("wall_thickness")
	var mid := (a + b) * 0.5
	if a.distance_to(b) < thick * 3.0 or _near_junction(mid, row, rows, thick * JUNCTION):
		return false
	var label := "%s: %s" % [holder.name, _label(row)]
	var across := (b - a).normalized().orthogonal()
	var in3d := _walls_along(t, mid + across * thick, mid - across * thick)
	t.check(in3d == 1, "%s: %d 3D wall twins meet its middle, not 1" % [label, in3d])
	return true


## Whether `point` lies within `reach` of the end of a segment that is not along `row`'s line.
func _near_junction(point: Vector2, row: Dictionary, rows: Array, reach: float) -> bool:
	var along: Vector2 = ((row["b"] as Vector2) - (row["a"] as Vector2)).normalized()
	for other: Dictionary in rows:
		var dir := ((other["b"] as Vector2) - (other["a"] as Vector2)).normalized()
		if absf(dir.dot(along)) > 0.99:
			continue
		for end: Vector2 in [other["a"], other["b"]]:
			if end.distance_to(point) < reach:
				return true
	return false


## How many wall twins the level ray from `from` to `to` (plan points) passes through.
func _walls_along(
	t: TestContext,
	from: Vector2,
	to: Vector2,
	height: float = RAY_HEIGHT,
) -> int:
	var space: PhysicsDirectSpaceState3D = t.world.twin_space().space()
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(from, height), PlanSpace.lift(to, height), PhysicsLayers.TWIN_WORLD
	)
	var counted := 0
	var skip: Array[RID] = []
	for _try in 8:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var owner := TwinSpace.owner_of(hit["collider"])
		if owner != null and owner.has_method(&"wall_segments"):
			counted += 1
		skip.append((hit["collider"] as CollisionObject3D).get_rid())
		query.exclude = skip
	return counted


## The length (px) along which two segments run on one line.
func _run_along(x: Dictionary, y: Dictionary) -> float:
	var xa: Vector2 = x["a"]
	var xb: Vector2 = x["b"]
	var dir := (xb - xa).normalized()
	var ya: Vector2 = y["a"]
	var yb: Vector2 = y["b"]
	if absf(dir.dot((yb - ya).normalized())) < 0.99:
		return 0.0
	if absf((ya - xa).dot(dir.orthogonal())) > OVERLAP:
		return 0.0
	var lo := maxf(0.0, minf((ya - xa).dot(dir), (yb - xa).dot(dir)))
	var hi := minf(xa.distance_to(xb), maxf((ya - xa).dot(dir), (yb - xa).dot(dir)))
	return maxf(0.0, hi - lo)


func _label(row: Dictionary) -> String:
	return "%s[%d] %s-%s" % [(row["wall"] as Node).name, row["index"], row["a"], row["b"]]
