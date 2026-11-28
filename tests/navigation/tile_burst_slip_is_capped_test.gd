extends GameTest
## A steering burst's landing is taken on a `GameClock` frame no bake landed on (`NavBake`'s one
## landing a frame), and a bake landing every frame holds it off `NavTileBurst.MOST_SLIP` frames, no
## more: it lands then, and takes that frame from a bake due on it.

const SEED := 7
const CORNER_IN := 100.0


func describe() -> Dictionary:
	return {
		"name": "A tile burst's wait for a free landing frame is capped",
		"description": "Bakes land on every frame from the burst's due one: it slips MOST_SLIP "
			+ "frames, then lands whatever, and the frame is taken.",
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
	var due_at := GameClock.frame() + NavBakeConfig.tile_frames
	var landed_on := -1
	for _i in NavBakeConfig.tile_frames + NavTileBurst.MOST_SLIP + 4:
		var frame := GameClock.frame()
		if frame >= due_at:
			NavBake.take_landing()  # a bake lands on every frame from the due one
		burst.step(region, site)
		if landed_on < 0 and NavPlan.polygon_of(tile) != before:
			landed_on = frame
			t.check(NavBake.landing_taken(), "the landing took its frame")
		await t.frames(1)
	t.expect_eq(
		landed_on,
		due_at + NavTileBurst.MOST_SLIP,
		"the burst landed after MOST_SLIP slipped frames, whatever",
	)
