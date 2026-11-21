extends GameTest
## The district's pre-warm files the flat art of a carried item under the key the match asks for
## (D21, `docs/stacked-items.md` SI14): a console's bowl is drawn `plain` (its own colour, not the
## run-down grade), and the warmed request holds that option and the colour as given, so the match
## finds the texture in the cache instead of painting it on the main thread.

const ItemPainter := preload("res://scenes/objects/art/item_painter.gd")


func describe() -> Dictionary:
	return {
		"name": "The pre-warm asks for a carried item as the match draws it",
		"description": "A warmed item request for the console's bowl holds `plain` and the "
			+ "row's colour as given.",
		"tags": ["worldgen", "art", "prewarm", "unbake"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var row := {}
	for carried: Dictionary in ObjectDefinitions.get_definition("console_table")["carries"]:
		if carried["key"] == "bowl":
			row = carried
	if not t.require(not row.is_empty(), "premise: the console carries a bowl"):
		return
	var want: Color = row["color"]
	var plain := 0
	for request: Dictionary in DistrictPrewarm.furniture_requests():
		var opts: Dictionary = request.get("opts", {})
		if (
			request.get("painter") == ItemPainter
			and opts.get("kind") == "bowl"
			and opts.get("plain", false)
			and request["color"] == want
		):
			plain += 1
	t.check(plain > 0, "a plain bowl in the row's colour is warmed (%d requests)" % plain)
