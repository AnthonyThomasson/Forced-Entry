extends GameTest
## Harness self-test: the held-picture helper (`tests/_render/frozen_frame.gd`) never waits for a
## frame to be drawn by itself. A window the desktop covers is not drawn, as a headless run is not,
## and `frame_post_draw` then never comes: the helper draws the frame on demand.

const Frozen := preload("res://tests/_render/frozen_frame.gd")


func describe() -> Dictionary:
	return {
		"name": "A held picture's draw never waits for a window that is not drawn",
		"description": "The helper that waits for a frame to be drawn returns with a frame drawn "
			+ "even when the main loop draws none.",
		"tags": ["harness", "render"],
		"timeout": 10.0,
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
