extends GameTest
## The grid baker's polygons are merged where the union is convex (`NavMerge`, #194): the
## same floor in fewer polygons, because a path query pays for every polygon it crosses (300
## queries across a district: 47 ms on the baker's own polygons, 28 merged, 24 on the 2D baker's).
## Pinned on a few hand-made meshes, and on a district's baked mesh: every polygon is convex, none
## has more than `NavMerge.MAX_CORNERS` corners and the merged area is the baker's.

const SEED := 7
## An L of three squares (side 10): a convex union is two of them, never all three.
const L_VERTICES := [
	Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(0, 10), Vector2(10, 10),
	Vector2(20, 10), Vector2(0, 20), Vector2(10, 20),
]
const L_SQUARES := [[0, 1, 4, 3], [1, 2, 5, 4], [3, 4, 7, 6]]
## Two squares a collinear vertex apart along their shared side's line: (0,0) (5,0) (10,0) is a
## straight run.
const RUN_VERTICES := [
	Vector2(0, 0), Vector2(5, 0), Vector2(10, 0), Vector2(0, 10), Vector2(5, 10), Vector2(10, 10),
]
const RUN_POLYGONS := [[0, 1, 4, 3], [1, 2, 5, 4]]
## The rings `NavMerge.merged` makes of them, vertex for vertex and in order: where each ring
## starts and which way it turns is what the server's fan reads, so a change to the merge's
## bookkeeping that keeps the polygons convex but turns a ring differently fails here.
const L_RINGS := [[4, 3, 0, 1, 2, 5], [3, 4, 7, 6]]
const RUN_RINGS := [[4, 3, 0, 1, 2, 5]]
## A ring the baker makes beside a carved door leaf: it visits vertex 1 twice, a spur of no width
## from vertex 0 (edges 0 -> 1 and 1 -> 0 are both in it), with a square beside it.
const SPUR_VERTICES := [
	Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10), Vector2(20, 0),
	Vector2(20, 10),
]
const SPUR_POLYGONS := [[0, 1, 2, 3, 1], [1, 4, 5, 2]]


func describe() -> Dictionary:
	return {
		"name": "The baked mesh's polygons are merged only where they stay convex",
		"description": "NavMerge fuses neighbouring polygons whose union is convex and small, "
			+ "keeps every vertex, starts a merged ring where its fan is sound, and a "
			+ "district's baked mesh has only convex polygons.",
		"tags": ["navigation", "bake", "district"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)


func run(t: TestContext) -> void:
	_check_hand_made(t)
	_check_spur(t)
	await t.seconds(0.5)
	_check_district(t)


func _check_hand_made(t: TestContext) -> void:
	var l_points := PackedVector2Array(L_VERTICES)
	var l_merged := NavMerge.merged(l_points, _rings(L_SQUARES))
	t.expect_eq(l_merged.size(), 2, "an L of three squares merges into two polygons, not one")
	for ring in l_merged:
		t.check(_convex(l_points, ring), "each polygon of the L is convex")
	t.expect_eq(_as_arrays(l_merged), L_RINGS, "the L's rings keep their vertex order")
	var points := PackedVector2Array(RUN_VERTICES)
	var run_merged := NavMerge.merged(points, _rings(RUN_POLYGONS))
	t.expect_eq(run_merged.size(), 1, "two squares side by side are one rectangle")
	t.expect_eq(_as_arrays(run_merged), RUN_RINGS, "the rectangle's ring keeps its vertex order")
	var rect := run_merged[0]
	t.expect_eq(rect.size(), 6, "the rectangle keeps its two straight-run vertices")
	var corners := [Vector2(0, 0), Vector2(10, 0), Vector2(0, 10), Vector2(10, 10)]
	t.check(
		points[rect[1]] in corners and points[rect[rect.size() - 1]] in corners,
		"the ring starts where both neighbours are corners (%s): the server's fan has no flat "
			% points[rect[0]] + "triangle",
	)


## A ring that is its own neighbour (it holds an edge and its reverse) is not merged with itself:
## it comes through whole, as the baker made it, where it once lost the polygon and logged a modulo
## by zero when its neighbours were next read.
func _check_spur(t: TestContext) -> void:
	var points := PackedVector2Array(SPUR_VERTICES)
	var merged := NavMerge.merged(points, _rings(SPUR_POLYGONS))
	t.check(merged.size() >= 1, "a ring with a spur comes through the merge")
	var kept := {}
	for ring in merged:
		t.check(not ring.is_empty(), "no ring is empty")
		for v in ring:
			kept[v] = true
	t.expect_eq(kept.size(), 6, "every vertex of the baker's polygons is still in a ring")
	t.check(
		_as_arrays(merged).any(func(r: Array) -> bool: return r.count(1) == 2),
		"the ring with the spur is kept as it was",
	)


func _check_district(t: TestContext) -> void:
	var region: NavigationRegion3D = t.world.find_children(
		"NavRegion", "NavigationRegion3D", true, false,
	)[0]
	var poly := NavPlan.polygon_of(region)
	var concave := 0
	var widest := 0
	for i in poly.get_polygon_count():
		var ring := poly.get_polygon(i)
		widest = maxi(widest, ring.size())
		if not _convex(poly.vertices, ring):
			concave += 1
	t.expect_eq(concave, 0, "every polygon of the district's mesh is convex")
	t.check(
		widest <= NavMerge.MAX_CORNERS,
		"no polygon has more than %d corners (%d)" % [NavMerge.MAX_CORNERS, widest],
	)


## `rings` as plain arrays of indexes, to compare with what a constant holds.
func _as_arrays(rings: Array[PackedInt32Array]) -> Array:
	var out := []
	for ring in rings:
		out.append(Array(ring))
	return out


func _rings(source: Array) -> Array[PackedInt32Array]:
	var rings: Array[PackedInt32Array] = []
	for ring: Array in source:
		rings.append(PackedInt32Array(ring))
	return rings


## Whether `ring` (indexes of `vertices`) turns one way all round (a straight corner is fine).
func _convex(vertices: PackedVector2Array, ring: PackedInt32Array) -> bool:
	var seen := 0.0
	for i in ring.size():
		var p := vertices[ring[i]]
		var turn := (vertices[ring[(i + 1) % ring.size()]] - p).cross(
			p - vertices[ring[(i + ring.size() - 1) % ring.size()]],
		)
		if absf(turn) <= 0.01:
			continue
		if seen != 0.0 and signf(turn) != seen:
			return false
		seen = signf(turn)
	return true
