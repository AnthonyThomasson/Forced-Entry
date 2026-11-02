extends GameTest
## A district's steering re-bake lands in the frame of the tick that measured the change too (#182):
## every match is a district. Its tick is staged, the planning gather a frame after the tiles'
## re-bake, but a walker held short of a body at rest looks for a way round it every `RECHECK` s
## and the steering map must not lag the tick (`steering_rebake_lands_in_its_tick_test.gd`). The
## first tick after a puppet moves already carries a new polygon on a tile, and so does the tick
## of a shoved piece of furniture, whose planning re-bake (its gather a frame later) lands too.

const TickLanding := preload("res://tests/_navigation/tick_landing_probe.gd")
const SEED := 7
## A character stands this far (px) in from the corner of the streets' rect, then moves along.
const CORNER_IN := 100.0
const MOVE := 300.0


func describe() -> Dictionary:
	return {
		"name": "A district re-bakes its steering tiles in the frame of the tick",
		"description": "A puppet stops 300 px further along a street; in the frame of the "
			+ "updater's next tick a steering tile already carries a new polygon.",
		"tags": ["navigation", "district", "rebake", "steering"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", true)
	s.actor(&"p", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district := t.world.get("district") as Node2D
	var region := t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	var tiles := NavBuilder.steering_regions(region as NavigationRegion2D)
	if not t.require(tiles.size() > 2, "premise: the steering map is many tiles"):
		return
	var front := WorldGen.district_bounds(district).position + Vector2(CORNER_IN, CORNER_IN)
	var puppet := t.actor(&"p")
	puppet.global_position = front
	await t.seconds(1.0)  # the tick that takes it in, and the planning bake after it
	var landing := TickLanding.new()
	landing.watch(t.world, tiles)
	puppet.global_position = front + Vector2(MOVE, 0)
	if not t.require(
		await t.until(func() -> bool: return landing.landed_at >= 0, 3.0),
		"a steering tile was re-baked after the puppet moved",
	):
		return
	t.expect_eq(
		landing.landed_at,
		1,
		"the first tick after the move already carries the re-bake (not the one after it)",
	)
	await _shoved_piece(t, region as NavigationRegion2D, tiles)


## A piece of furniture shoved 100 px: the same tick re-bakes the tiles round it, and the planning
## region (its gather a frame after) is re-baked within the next ticks.
func _shoved_piece(
	t: TestContext,
	region: NavigationRegion2D,
	tiles: Array[NavigationRegion2D],
) -> void:
	var district := t.world.get("district") as Node2D
	var piece: RigidBody2D = null
	for body in district.find_children("*", "RigidBody2D", true, false):
		if not body.find_children("*", "CollisionShape2D", true, false).is_empty():
			piece = body
			break
	if not t.require(piece != null, "premise: the district has a solid piece of furniture"):
		return
	await t.seconds(1.0)
	var planning_before := region.navigation_polygon
	var landing := TickLanding.new()
	landing.watch(t.world, tiles)
	piece.global_position += Vector2(100, 0)
	if not t.require(
		await t.until(func() -> bool: return landing.landed_at >= 0, 3.0),
		"a steering tile was re-baked after the piece was shoved",
	):
		return
	t.expect_eq(landing.landed_at, 1, "the shove's tick already carries the tiles' re-bake")
	t.check(
		await t.until(
			func() -> bool: return region.navigation_polygon != planning_before,
			3.0,
		),
		"the planning region is re-baked after the shove, a frame after the tiles",
	)
