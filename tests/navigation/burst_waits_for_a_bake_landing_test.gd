extends GameTest
## A steering burst's landing and a planning bake's never share a `GameClock` frame (`NavBake`'s
## one landing a frame): each assigns polygons and makes a map synchronise, and a frame that held
## both paid both. A burst due on a frame a landing has taken waits for the next one.

const SEED := 7
const CORNER_IN := 100.0


func describe() -> Dictionary:
	return {
		"name": "A tile burst's landing waits a frame for a bake's",
		"description": "A burst of one tile comes due on a frame a landing has taken: the tile "
			+ "keeps its polygon that frame and takes the new one on the next.",
		"tags": ["navigation", "district", "steering", "bake"],
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
		WorldGen.district_bounds(district).position + Vector2(CORNER_IN, CORNER_IN)
	)
	await t.frames(3)
	var due := NavTiles.due_tiles(
		region, site, NavBuilder.furniture_holes(district),
		NavBuilder.character_holes(district.get_parent()),
	)
	if not t.require(not due.is_empty(), "premise: a tile is due"):
		return
	var tile := due[0]["tile"] as NavigationRegion3D
	var before := NavPlan.polygon_of(tile)
	var burst := NavTileBurst.new()
	burst.begin([due[0]])
	var started := GameClock.frame()
	var landed_on := -1
	for _i in NavBakeConfig.tile_frames + 4:
		var frame := GameClock.frame()
		if frame == started + NavBakeConfig.tile_frames:
			NavBake.take_landing()  # a bake landed on the burst's due frame
		burst.step(region, site)
		if landed_on < 0 and NavPlan.polygon_of(tile) != before:
			landed_on = frame
		await t.frames(1)
	t.check(landed_on >= 0, "the burst landed")
	t.expect_eq(
		landed_on,
		started + NavBakeConfig.tile_frames + 1,
		"the burst slipped one frame past the one a landing took",
	)
