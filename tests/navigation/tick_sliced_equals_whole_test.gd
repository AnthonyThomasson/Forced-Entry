extends GameTest
## A district's updater tick is made in steps (`NavTick`): the footprints read a slice of pieces a
## frame, the tiles due found a slice of tiles a frame. Run to its end it holds what a tick made
## at once holds (`NavBuilder.furniture_holes`, `NavBuilder.character_holes`, `NavTiles.due_tiles`),
## no step reads more pieces than `NavTick.SCAN` or cuts more than `NavTick.CUTS`, and it takes
## more than one step (the work is spread, not just moved).

const SEED := 7


func describe() -> Dictionary:
	return {
		"name": "A district's sliced tick finds what a whole tick finds",
		"description": "NavTick run step by step makes the same footprints and the same due tiles "
			+ "as the calls made at once, and takes several steps.",
		"tags": ["navigation", "district", "rebake", "perf"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)
	s.actor(&"p", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district := t.world.get("district") as Node2D
	var region := t.world.find_children("NavRegion", "NavigationRegion3D", true, false)[0]
	var site := NavBuilder.site_of(region, district, WorldGen.district_rooms(district))
	t.actor(&"p").global_position = (
		WorldGen.district_bounds(district).position + Vector2(100.0, 100.0)
	)
	await t.frames(3)
	# A baseline of nothing: everything moved, so the tick runs to the due tiles.
	var tick := NavTick.new(region, district, site, [[], []], 4.0)
	var steps := 1
	while not tick.step():
		steps += 1
		if steps > 200:
			break
	t.check(steps > 2 and steps <= 200, "the tick took several steps (%d)" % steps)
	t.check(tick.moved and tick.furniture_moved, "an empty baseline reads as moved")
	t.expect_eq(
		tick.furniture,
		NavBuilder.furniture_holes(district),
		"the footprints equal a whole read",
	)
	t.expect_eq(
		tick.characters, NavBuilder.character_holes(district.get_parent()), "and the characters'")
	var whole := NavTiles.due_tiles(
		region, site, tick.furniture, tick.characters,
		NavTiles.walking_at(district.get_parent()),
	)
	t.expect_eq(
		tick.due.size(),
		whole.size(),
		"the tiles due are as many as at once (%d)" % whole.size(),
	)
	t.check(_same(tick.due, whole), "in the same order, each with the same holes")
	_cut_bound(t, district)


## No step cuts more footprints than `CUTS`, however many pieces are dirty.
func _cut_bound(t: TestContext, district: Node2D) -> void:
	var pieces := NavPieces.of(district)
	pieces.begin_holes()
	var worst := 0
	var done := false
	while not done:
		var before := NavHoles.cuts
		done = pieces.step_holes(NavTick.SCAN, NavTick.CUTS)
		worst = maxi(worst, NavHoles.cuts - before)
	t.check(worst <= NavTick.CUTS, "a step cuts at most CUTS footprints (%d)" % worst)


## Whether the due tiles `a` and `b` are the same tiles with the same holes, in the same order.
func _same(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i]["tile"] != b[i]["tile"] or a[i]["holes"] != b[i]["holes"]:
			return false
	return true
