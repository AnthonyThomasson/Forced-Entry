extends GameTest
## Where an ambush order's members wait (`docs/leadership.md` LD15, D17) is the full ranking's,
## though an entry's grenade landings are counted only where they can still decide a pick: in a
## generated house (the match guards' house, seed 7 on the largest plan, garage_home, furnished),
## for every doorway laid from each room it joins and every member of an order to one to six, the
## post is the one `ambush_posts_capture_house.json` beside this test holds, a capture of the
## ranking with every post's landings counted (`tests/_ai/ambush_posts_probe.gd`). No actors: the
## posts are read through the published entry geometry with no NPC, which keeps a ranking of its
## own, worked out as the one every NPC on the map shares; the shared ranking itself runs in
## `ai/combat/ambush_post_cover_through_body`, `perf/ambush_order_stress` and the crew scenarios.

const AmbushPosts := preload("res://tests/_ai/ambush_posts_probe.gd")
## The house: the match guards' (`tests/_perf/perf_probe.gd` `MATCH_SEED`, `MATCH_PLAN`).
const SEED := 7
const PLAN := "garage_home"
const CAPTURE := "res://tests/ai/combat/ambush_posts_capture_house.json"


func describe() -> Dictionary:
	return {
		"name": "Ambush posts in a generated house match the capture",
		"description": "Every member's ambush post at every doorway of a generated house, "
			+ "from each room it joins, is the full ranking's held in the capture (LD15, D17, "
			+ "#128).",
		"tags": ["ai", "combat", "leadership", "ambush", "scripted", "regression"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)


func run(t: TestContext) -> void:
	await t.frames(2)
	AmbushPosts.check_capture(t, CAPTURE)
