extends GameTest
## Where an ambush order's members wait (`docs/leadership.md` LD15, D17) is unchanged by the cheaper
## ranking of the posts (issue #128's review: an entry's grenade landings counted only where they
## can still decide a pick, and the ranking shared by every NPC on the map): in the furnished
## Terrace house, for every doorway laid from each room it joins and every member of an order to one
## to six, the post is the one `ambush_posts_capture_terrace.json` beside this test captured on the
## code before (`tests/_ai/ambush_posts_probe.gd`). No actors: the posts are read through the
## published entry geometry.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const AmbushPosts := preload("res://tests/_ai/ambush_posts_probe.gd")
const CAPTURE := "res://tests/ai/combat/ambush_posts_capture_terrace.json"


func describe() -> Dictionary:
	return {
		"name": "Ambush posts in the Terrace house match the capture",
		"description": "Every member's ambush post at every doorway of the furnished Terrace "
			+ "house, from each room it joins, is the one captured before the ranking was made "
			+ "cheaper (LD15, D17, #128).",
		"tags": ["ai", "combat", "leadership", "ambush", "scripted", "regression"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)


func run(t: TestContext) -> void:
	await t.frames(2)
	AmbushPosts.check_capture(t, CAPTURE)
