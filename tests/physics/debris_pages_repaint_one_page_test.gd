extends GameTest
## A debris chunk holds its resting chips in pages of `DebrisLayer.PAGE`, oldest first, each page
## a canvas item of its own, so a chip coming to rest repaints the page it joins and the oldest
## chip dropped at the cap repaints the page it leaves, not every chip in the chunk (a struck chair
## throws dozens of chips a second into one chunk, which held hundreds). The pages keep the chunk's
## chips in order, and a page left empty goes.

## Chips laid in one chunk before measuring: several pages' worth.
const LAID := 200


func describe() -> Dictionary:
	return {
		"name": "A resting chip repaints one page of its chunk",
		"description": "Debris chunks draw their chips in pages: a chip landing, or the oldest "
			+ "dropped at the cap, repaints only its page; the pages hold the chunk's chips in "
			+ "order.",
		"tags": ["debris", "draw", "physics"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.set_static(DebrisLayer, &"paged", true)


func run(t: TestContext) -> void:
	var layer := DebrisLayer.layer(t.world)
	var cap_before: int = Despawner.max_scene_objects
	for i in LAID:
		_rest_one(layer, i)
	await t.frames(2)
	var cell := Vector2i(0, 0)
	t.check(
		layer.marks_in(cell).size() == LAID,
		"the chips lie in one chunk (%d)" % layer.marks_in(cell).size(),
	)

	DebrisLayer.chips_drawn = 0
	_rest_one(layer, LAID)
	await t.frames(2)
	t.check(
		DebrisLayer.chips_drawn > 0 and DebrisLayer.chips_drawn <= DebrisLayer.PAGE,
		"a chip landing repaints at most a page (%d chips drawn, page %d)"
			% [DebrisLayer.chips_drawn, DebrisLayer.PAGE],
	)

	Despawner.max_scene_objects = layer.count()
	DebrisLayer.chips_drawn = 0
	_rest_one(layer, LAID + 1)  # one more lands, the oldest goes
	await t.frames(2)
	t.check(
		DebrisLayer.chips_drawn > 0 and DebrisLayer.chips_drawn <= 2 * DebrisLayer.PAGE,
		"at the cap, landing and dropping repaint the last and the first page (%d chips drawn)"
			% DebrisLayer.chips_drawn,
	)

	Despawner.max_scene_objects = DebrisLayer.PAGE + 3  # drop all but the newest few pages' worth
	_rest_one(layer, LAID + 2)
	await t.frames(2)
	var chunk: Node = layer._chunks[cell]
	var paged: Array = []
	for page in chunk.get_children():
		if page.is_queued_for_deletion():
			continue
		t.check(not page.chips.is_empty(), "no page is left empty")
		paged.append_array(page.chips)
	t.check(
		paged == layer.marks_in(cell),
		"the pages hold the chunk's chips, oldest first (%d paged, %d in the chunk)"
			% [paged.size(), layer.marks_in(cell).size()],
	)
	Despawner.max_scene_objects = cap_before


## Lay chip `i` to rest inside the first chunk, its shape, turn and colour varying with `i`.
static func _rest_one(layer: DebrisLayer, i: int) -> void:
	var shapes := ["rect", "tri", "circle"]
	layer.rest(
		Vector2(20.0 + (i % 17) * 5.0, 20.0 + (floori(i / 17.0) % 17) * 5.0),
		i * 0.37,
		Color.from_hsv(fmod(i * 0.13, 1.0), 0.6, 0.8),
		Vector2(3.0, 4.0),
		shapes[i % 3],
	)
