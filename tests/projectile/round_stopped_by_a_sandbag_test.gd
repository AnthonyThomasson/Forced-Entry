extends GameTest
## A sandbag stops a pistol round (#194, D21, `docs/stacked-items.md` SI15): the barricade
## gave up its sandbags as loose items and a bag of sand stops a round as the barricade it flanked
## did (`penetration` 90). A bag is shot from the front, level with its middle, a dummy a step
## behind it: the round hits the bag and the dummy is not hit. The mutant that gives the bag a
## paper's penetration (20) lets it through and this goes red.

const SHOOTER_GAP := 160.0
const TARGET_GAP := 14.0
const AT := Vector2(400, 300)
## The height (px) of the bag's middle: it is 10 high.
const MIDDLE := 5.0


func describe() -> Dictionary:
	return {
		"name": "A sandbag stops a pistol round",
		"description": "A loose sandbag shot level with its middle from the front with a dummy "
			+ "behind it: the round hits the bag and does not reach the dummy.",
		"tags": ["items", "bullets", "penetration", "projectile", "unbake"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	s.object(&"bag", "sandbag", AT)
	s.actor(&"shooter", &"puppet", AT + Vector2(0, SHOOTER_GAP), { "start_slot": 3 })
	s.actor(
		&"dummy", &"puppet", AT - Vector2(0, 4.0 + TARGET_GAP),
		{ "max_health": 500.0, "faction": &"dummy" },
	)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var bag: Node2D = t.object(&"bag")
	var dummy: Node2D = t.actor(&"dummy")
	t.expect_eq(
		float(ObjectDefinitions.get_definition("sandbag")["penetration"]), 90.0,
		"a sandbag's penetration is the barricade's (90)",
	)
	await t.seconds(1.5)
	var puppet := t.puppet(&"shooter")
	puppet.aim_at(bag.global_position, MIDDLE)
	await t.seconds(0.5)
	puppet.shoot()
	await t.seconds(0.5)
	t.check(
		t.events_of(&"hit", func(d): return d["victim"] == bag).size() >= 1,
		"the pistol's round hit the sandbag",
	)
	t.check(
		t.events_of(&"hit", func(d): return d["victim"] == dummy).is_empty(),
		"the round did not go through the sandbag to the dummy",
	)
