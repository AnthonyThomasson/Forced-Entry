extends GameTest
## D20 / SI9 (#194 stack-b review M1): an item is placed only where its whole footprint fits. On a
## floor stack each item lies inside the footprint of the one under it (a crate stands on a crate,
## a box on a box or a crate, never a crate on a box) and on a flat top it lies inside the piece's
## main top and clear of any part that rises over it (a counter's backsplash). Over a sample of
## seeded houses and a district's towers.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const CounterMesh := preload("res://scenes/objects/art/counter_mesh.gd")
const PLANS := [
	"starter_home",
	"open_plan_home",
	"bungalow",
	"garage_home",
	"two_bed_flat",
	"office_loft",
]
const SEEDS := [2, 5, 9, 11, 13, 16, 21, 3, 4, 6, 7, 8]
## Slack (px) for float rounding.
const EPS := 0.05


func describe() -> Dictionary:
	return {
		"name": "Items lie inside what they stand on",
		"description": "Floor stacks never put a bigger item on a smaller; an item on a top lies "
			+ "inside the main top and off a backsplash; over seeded houses and a district.",
		"tags": ["worldgen", "stacking", "determinism", "house", "district"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.district(11, "")


func run(t: TestContext) -> void:
	var stats := { "stacked": 0, "tops": 0 }
	for tower: Dictionary in DistrictReads.get_towers(t.world.district):
		_check(t, "district 11", RoomItems.placed_in(tower["node"]), stats)
	for plan_key: String in PLANS:
		if not plan_key in HouseDefinitions.get_all():
			continue
		for house_seed: int in SEEDS:
			var house := Houses.generated(t, plan_key, house_seed)
			_check(t, "%s seed %d" % [plan_key, house_seed], RoomItems.placed_in(house), stats)
			house.queue_free()
			await t.frames(1)
	t.check(stats["stacked"] > 20, "a sample of stacked items (%d)" % stats["stacked"])
	t.check(stats["tops"] > 100, "a sample of items on tops (%d)" % stats["tops"])


## Every item of `placed` (`RoomItems.placed_in`) against what it stands on.
func _check(t: TestContext, where: String, placed: Array, stats: Dictionary) -> void:
	var under: Dictionary = {}
	for entry: Dictionary in placed:
		var node: Node2D = entry["node"]
		var base: Variant = entry["on"]
		if entry.get("carried", false):
			continue  # Carried (unbake, D21): it stands on a board, a pallet or a crate.
		if base == null:
			under[node] = node
			continue
		var mine := Rect2(node.global_position - node.size * 0.5, node.size)
		if under.has(base):
			stats["stacked"] += 1
			var below: Node2D = under[base]
			var lower := Rect2(below.global_position - below.size * 0.5, below.size)
			t.check(
				lower.grow(EPS).encloses(mine),
				"%s: %s lies inside the %s under it (%s on %s)" % [
					where, node.name, below.name, mine, lower,
				],
			)
			under[base] = node
			continue
		stats["tops"] += 1
		_check_top(t, where, node, mine, base as Node2D)


## The item `node` (footprint `mine`) on the furniture `base`: inside its top, off what rises. The
## top and the lip are derived here from the piece's own data (`PieceHeights.parts`, the counter's
## `CounterMesh.splash_of`), not read back from `ObjectFactory.flat_top` that placed the item.
func _check_top(t: TestContext, where: String, node: Node2D, mine: Rect2, base: Node2D) -> void:
	var spec := FurnitureSpec.of(base)
	var parts := PieceHeights.parts(spec)
	var lowest := INF
	for part: Dictionary in parts:
		lowest = minf(lowest, part["top"])
	var top := _world_rect(base, spec, Rect2(0.0, 0.0, spec.size.x, spec.size.y))
	t.check(
		top.grow(EPS).encloses(mine),
		"%s: %s lies inside the top of %s" % [where, node.name, base.name],
	)
	var lips: Array[Rect2] = []
	for part: Dictionary in parts:
		if part["top"] > lowest + 0.5:
			var unit: Rect2 = part["rect"]
			lips.append(_world_rect(base, spec, Rect2(
				unit.position * spec.size, unit.size * spec.size,
			)))
	var splash := CounterMesh.splash_of(spec)
	if spec.art == "counter" and splash > 0.0:
		lips.append(_world_rect(base, spec, Rect2(0.0, 0.0, spec.size.x, splash)))
	for part in lips:
		t.check(
			not part.intersects(mine),
			"%s: %s is off the lip of %s" % [where, node.name, base.name],
		)
	if spec.art == "counter" and splash > 0.0:
		t.check(lips.size() > 0, "%s: a counter's backsplash is a lip" % where)


## `area` (px from the piece's back-left corner, in its painter's frame) as a world rect, turned
## the way `base` faces.
func _world_rect(base: Node2D, spec: FurnitureSpec, area: Rect2) -> Rect2:
	var centre := area.position + area.size * 0.5 - spec.size * 0.5
	var turned := centre.rotated(spec.turns * PI * 0.5)
	var plan := Vector2(area.size.y, area.size.x) if spec.turns % 2 == 1 else area.size
	var at := (base.get_parent() as Node2D).to_global(base.position + turned)
	return Rect2(at - plan * 0.5, plan)
