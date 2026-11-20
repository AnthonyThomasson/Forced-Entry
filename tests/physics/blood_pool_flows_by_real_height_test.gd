extends GameTest
## A bleed-out pool lies on the floor, so what blocks it is what stands on the floor in the twin 3D
## space (#194 del2d): a desk (0 to 31 px) is walked round, a mirror hanging from 46 px is flowed
## under, and the arena's walls hold it in.

const ORIGIN := Vector2(200, 250)
const MIRROR_AT := Vector2(300, 250)
const DESK_AT := Vector2(500, 250)
## The footprints (px) of the mirror (44 by 12) and the desk (120 by 50), as the catalogue has them.
const MIRROR := Vector2(44, 12)
const DESK := Vector2(120, 50)
const ARENA := Rect2(0, 0, 900, 500)
const CELLS := 30_000


func describe() -> Dictionary:
	return {
		"name": "A bleed-out pool flows by what stands on the floor",
		"description": "The flood-fill claims the floor under a mirror hung at 46 px and never "
			+ "the floor a desk stands on or the floor beyond the arena's walls.",
		"tags": ["blood", "pool", "heights", "3d"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", true)
	s.object(&"mirror", "mirror", MIRROR_AT)
	s.object(&"desk", "desk", DESK_AT)


func run(t: TestContext) -> void:
	await t.frames(3)
	var space := TwinSpace.space_of(t.world)
	if not t.require(space != null, "premise: the world has a twin space"):
		return
	seed(194)
	var flow := BloodFlow.new(Vector2.RIGHT, [])
	flow.step(CELLS, space, ORIGIN, CELLS)
	t.check(
		flow.cells.size() > 1000,
		"the pool spreads over the floor (%d cells)" % flow.cells.size(),
	)
	var under := _cells_in(Rect2(MIRROR_AT - MIRROR / 2.0, MIRROR))
	t.check(not under.is_empty(), "premise: cells lie under the mirror (%d)" % under.size())
	t.check(_all_claimed(flow, under), "the floor under the hanging mirror is claimed")
	var beneath := _cells_in(Rect2(DESK_AT - DESK / 2.0, DESK))
	t.check(not beneath.is_empty(), "premise: cells lie under the desk (%d)" % beneath.size())
	t.check(_none_claimed(flow, beneath), "the floor under the desk is not")
	var outside := 0
	for c: Vector2i in flow.cells:
		if not ARENA.has_point(ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * 4.0):
			outside += 1
	t.expect_eq(outside, 0, "no claimed cell lies outside the arena's walls")


## The grid cell of the flow (its origin `ORIGIN`) that holds world point `at`.
func _cell_of(at: Vector2) -> Vector2i:
	return Vector2i(((at - ORIGIN) / BloodPoolConfig.flow_cell_size).floor())


## The grid cells whose centres lie inside `rect`.
func _cells_in(rect: Rect2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in range(-120, 120):
		for r in range(-60, 60):
			var cell := Vector2i(c, r)
			var size := BloodPoolConfig.flow_cell_size
			var centre := ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * size
			if rect.has_point(centre):
				cells.append(cell)
	return cells


## Whether the flow claimed every one of `cells`.
func _all_claimed(flow: BloodFlow, cells: Array[Vector2i]) -> bool:
	return cells.all(func(c: Vector2i) -> bool: return flow.covers(c))


## Whether the flow claimed none of `cells`.
func _none_claimed(flow: BloodFlow, cells: Array[Vector2i]) -> bool:
	return not cells.any(func(c: Vector2i) -> bool: return flow.covers(c))
