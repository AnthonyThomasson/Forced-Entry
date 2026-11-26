extends GameTest
## A held avoid bake is made from the planning bake's source as it is when the bake starts, so a
## planning re-bake made while it waits is in it, and it is not baked a second time
## (`domain-navigation` `rebake.md`, "A bake waits its turn"). With one bake at a time, a chair is
## moved and the planning map re-baked while an avoid map is held: that map lands with the chair
## where it stands now.

const ARENA := Rect2(0, 0, 900, 500)
const WAS := Vector2(200, 250)
const NOW := Vector2(650, 250)
const WAIT := 20


func describe() -> Dictionary:
	return {
		"name": "A held avoid bake takes the newest planning bake",
		"description": "A chair moved and re-baked while an avoid map is held is carved where it "
			+ "stands now, and asking again bakes nothing more.",
		"tags": ["navigation", "bake", "avoid", "rebake"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", WAS)
	s.set_static(NavBakeConfig, &"at_once", 1)
	s.set_static(NavBakeConfig, &"house_frames", WAIT)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region := NavBuilder.planning_region(NavWorld.map_of(t.world))
	if not t.require(region != null, "the planning region is found from the world's map"):
		return
	NavBuilder.avoid_map(region, "first", [])
	var held := NavBuilder.avoid_map(region, "held", [])
	t.object(&"chair").global_position = NOW
	await t.frames(TwinSpace.PARK_SPREAD + 2)
	NavBuilder.rebake(region, t.world.house, t.rooms)
	if not t.require(
			await t.until(func(): return NavBuilder.ready(held), 3.0),
			"the held map lands",
	):
		return
	var started := NavBake.started_total
	NavBuilder.avoid_map(region, "held", [])
	t.expect_eq(NavBake.started_total, started, "asked again, nothing more is baked")
	await t.frames(2)
	t.check(
		NavPlan.closest(held, NOW).distance_to(NOW) > 8.0,
		"the chair is carved where it stands now",
	)
	t.check(
		NavPlan.closest(held, WAS).distance_to(WAS) < 2.0,
		"and the floor it left is open",
	)
