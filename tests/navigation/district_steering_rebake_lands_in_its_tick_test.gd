extends GameTest
## A district's steering re-bake of the tick that measured a change lands together within its
## burst's frames (#195; a lone house's lands in the tick itself,
## `steering_rebake_lands_in_its_tick_test.gd`). A walker held short of a body at rest looks for a
## way round it every `RECHECK` s, and the steering map must not lag by more than the burst. The
## tick bakes the first due tile (the walker's own) and the updater one more a physics frame, and
## the last lands them all at once: one steering-map synchronisation, so the walker sees the
## re-bake up to as many frames after the tick as tiles are due (`tile_rebake_one_a_frame_test.gd`
## holds the order and the one a frame). The tiles a puppet's stop makes due, and those a shoved
## piece of furniture makes due, land on one frame within their count of frames of the first
## bake; the shove's planning re-bake (its gather over the next frames) lands too.

const SEED := 7
## A character stands this far (px) in from the corner of the streets' rect, then moves along.
const CORNER_IN := 100.0
const MOVE := 300.0
## How long (sim s) the planning region's re-bake may take to land: its bake runs on the server's
## worker thread in real time, and a headless run's frames are far shorter than that.
const PLANNING_WAIT := 12.0
## Physics frames to wait for the change's first bake (a tick is 45 frames), and to watch after it.
const WAIT_FRAMES := 70
const AFTER_FRAMES := 20


func describe() -> Dictionary:
	return {
		"name": "A district lands its steering tiles together within the burst's frames",
		"description": "A puppet stops 300 px further along a street: the tiles it makes due are "
			+ "baked one a frame and land on one frame, within as many frames as there are tiles.",
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
	puppet.global_position = front + Vector2(MOVE, 0)
	await _lands_together(t, tiles, "the puppet moved")
	await _shoved_piece(t, region as NavigationRegion2D, tiles)


## After a change was made: the tiles it made due landed on one frame, within as many frames as
## there are tiles of the first bake (the tick's), and no two were baked on one frame. Samples every
## physics frame until `AFTER_FRAMES` after the first bake, the next tick being 45 frames on.
func _lands_together(
	t: TestContext,
	tiles: Array[NavigationRegion2D],
	what: String,
) -> void:
	var before := _polygons(tiles)
	var prepared := NavTiles.baked_total
	var first := -1
	var worst := 0
	var landing_frames := []
	var landed := 0
	for frame in WAIT_FRAMES:
		await t.frames(1)
		var baked := NavTiles.baked_total - prepared
		prepared = NavTiles.baked_total
		worst = maxi(worst, baked)
		if baked > 0 and first < 0:
			first = frame
		var now := _changed(tiles, before)
		if now > landed:
			landing_frames.append(frame)
			landed = now
		if first >= 0 and frame - first > AFTER_FRAMES:
			break
	if not t.require(first >= 0 and landed > 0, "tiles were baked and landed after: " + what):
		return
	t.expect_eq(worst, 1, "no frame baked two tiles (after: %s)" % what)
	t.expect_eq(
		landing_frames.size(),
		1,
		"the tiles landed on one frame (%s)" % str(landing_frames),
	)
	t.check(
		landing_frames[0] - first <= landed - 1,
		"%d tile(s) landed within %d frame(s) of the first bake (first %d, landed %s)"
			% [landed, landed, first, str(landing_frames)],
	)


## Every tile's polygon now.
func _polygons(tiles: Array[NavigationRegion2D]) -> Array:
	return tiles.map(
		func(tile: NavigationRegion2D) -> NavigationPolygon: return tile.navigation_polygon,
	)


## How many of `tiles` carry another polygon than `before`.
func _changed(tiles: Array[NavigationRegion2D], before: Array) -> int:
	var count := 0
	for i in tiles.size():
		if tiles[i].navigation_polygon != before[i]:
			count += 1
	return count


## A piece of furniture shoved 100 px: the same tick re-bakes the tiles round it, and the planning
## region (its gather over the next frames, swapped in whole) is re-baked within the next ticks.
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
	piece.global_position += Vector2(100, 0)
	await _lands_together(t, tiles, "the piece was shoved")
	t.check(
		await t.until(
			func() -> bool: return region.navigation_polygon != planning_before,
			PLANNING_WAIT,
		),
		"the planning region is re-baked after the shove, after the tiles",
	)
