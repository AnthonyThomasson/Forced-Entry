extends GameTest
## Harness self-test: the held-picture helper (`tests/_render/frozen_frame.gd`) never waits for a
## frame to be drawn by itself. A window the desktop covers is not drawn, as a headless run is not,
## and `frame_post_draw` then never comes: the helper draws the frame on demand. And the wait for a
## stopped picture to settle says no when it never does, so a test fails rather than compares two
## pictures that were still changing.

const Frozen := preload("res://tests/_render/frozen_frame.gd")


func describe() -> Dictionary:
	return {
		"name": "A held picture's draw never waits for a window that is not drawn",
		"description": "The helper that waits for a frame to be drawn returns with a frame drawn "
			+ "even when the main loop draws none, and waiting for a picture that never settles "
			+ "says no.",
		"tags": ["harness", "render"],
		"timeout": 40.0,
		"internal": true,
	}


func run(t: TestContext) -> void:
	var tree := t.world.get_tree()
	var draws := [0]
	var count := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count)
	for i in 3:
		await tree.process_frame
	if DisplayServer.get_name() == "headless":
		t.require(draws[0] == 0, "premise: the main loop draws no frame (%d)" % draws[0])
	var before: int = draws[0]
	await Frozen.drawn(tree)
	t.check(draws[0] > before, "a frame is drawn by the time it returns")
	RenderingServer.frame_post_draw.disconnect(count)
	await _settles(t, tree)


## A picture that stays settles after `SETTLED_FRAMES` drawn frames; one that never stays does not.
func _settles(t: TestContext, tree: SceneTree) -> void:
	var still := Image.create(4, 4, false, Image.FORMAT_RGB8)
	var draws := [0]
	var count := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count)
	var settled: bool = await Frozen.settle(tree, func() -> Image: return still)
	t.check(settled, "a picture that stays the same settles")
	t.check(
		draws[0] >= Frozen.SETTLED_FRAMES,
		"only after that many frames are drawn (%d)" % draws[0],
	)
	var taken := [0]
	var changing := func() -> Image:
		taken[0] += 1
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color.WHITE if taken[0] % 2 == 0 else Color.BLACK)
		return image
	draws[0] = 0
	settled = await Frozen.settle(tree, changing)
	t.check(not settled, "a picture that never stays the same does not")
	t.check(
		draws[0] >= Frozen.MOST_FRAMES,
		"it is waited for until that many frames are drawn (%d)" % draws[0],
	)
	RenderingServer.frame_post_draw.disconnect(count)
