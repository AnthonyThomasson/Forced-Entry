extends GameTest
## A lone house's steering re-bake lands in the frame of the tick that measured the change (#182).
## A walker held short of a body at rest looks for a way round it every `RECHECK` s, and the
## steering map answers one frame after the re-bake: a re-bake a frame later than the tick lands
## that look a frame short, and the walker waits a whole `RECHECK` more, which moved
## `ai/entry/entry_team_flows_in` from 9% to 24% failures. The first tick after a puppet moves
## already carries the new polygon (`district_steering_rebake_lands_in_its_tick_test.gd` is the
## same for a district's tiles).

const TickLanding := preload("res://tests/_navigation/tick_landing_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A lone house re-bakes its steering map in the frame of the tick",
		"description": "A puppet teleports across the arena; in the frame of the updater's next "
			+ "tick the steering region already carries the new polygon, not a frame later.",
		"tags": ["navigation", "rebake", "steering"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 300))
	s.switch(&"nav.rebake", true)
	s.actor(&"p", &"puppet", Vector2(100, 150))


func run(t: TestContext) -> void:
	var region := t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	var steering := NavBuilder.steering_regions(region as NavigationRegion2D)
	if not t.require(steering.size() == 1, "premise: a lone house has one steering region"):
		return
	# The first tick has taken the puppet in; none is under way.
	await t.seconds(1.0)
	var landing := TickLanding.new()
	landing.watch(t.world, steering)
	t.actor(&"p").global_position = Vector2(480, 150)
	if not t.require(
		await t.until(func() -> bool: return landing.landed_at >= 0, 3.0),
		"the steering map was re-baked after the puppet moved",
	):
		return
	t.expect_eq(
		landing.landed_at,
		1,
		"the first tick after the move already carries the re-bake (not the one after it)",
	)
