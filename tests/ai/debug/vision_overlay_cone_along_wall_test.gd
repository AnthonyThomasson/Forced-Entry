extends GameTest

## The vision overlay (AI debug, `scenes/ai/debug/vision_debug.gd`) draws an NPC's view cone however its sight ends: ticket #65's
## `ai/entry/entry_team_no_bumping` logged "Invalid polygon data, triangulation failed." whenever an invader stood or walked a few dozen px
## off a straight wall looking along it. Each ray of the cone ends where the NPC's sight does (`debug_sight_end`), so a run of ends on one
## wall lies on one line up to float noise (three neighbours' cross product +-1e-6, some of them reading as reflex corners), and the
## engine's own cut of that polygon (`draw_polygon` triangulates it again) found no ear and drew nothing. The cone is star-shaped from the
## eye by construction, so the overlay draws it as that fan.
##
## The two poses that failed, as their cones' exact bytes (the 65 ray ends after the eye, in the overlay's frame): the invader 24.55 px
## off the house's front wall outside, walking west to its stack slot and looking up along the wall at the front door (railroad_flat
## seed 3, 15.4 s), and an invader inside the vestibule walking south at the front wall 40.16 px off (57.2 s). A fake controller answers
## the overlay's sight rays with those ends (the body at the origin, so the overlay's `to_local` hands them on bit for bit), and the
## overlay must draw each cone whole: no logged error, and its triangles (`drawn()`) covering the cone's area, and the bubble's.

const VISION_SCRIPT := "res://scenes/ai/debug/vision_debug.gd"
## How far the fake's bubble and cone rays reach (px): apart, so it tells a cone ray from a bubble ray by its length.
const AWARENESS := 50.0
const VIEW := 500.0
## Each failing pose: its facing (the cone's rays fan round it) and its cone as `var_to_bytes` hex (the eye, then the 65 ray ends).
const POSES := [
	{
		"name": "inside, at the front wall",
		"facing": Vector2(-0.372533, 0.928019),
		"cone": "23000000420000000000000000000000d0abd1412ba520423030c4412ba52042e030b7412ba5204270a1aa412ba52042e0769e412ba5204230a792412ba52042302987412ba5204220e977412ba52042200362412ba5204240924c412ba52042408937412ba52042c0db22412ba52042407e0e412ba5204240cbf4402ba52042c00ecd402ca5204280b3a5402aa52042804b7d402ba5204200a62f402aa5204200a3c43f2ba520420058a93e2ba5204200c85fbf2ba52042002905c02ba52042809d52c02ba52042c03990c02ca520424068b7c02ba5204200eddec02ba52042c06d03c12ba5204220a417c12ba5204240242cc12ba52042a0f940c12ba52042e02f56c12ba52042e0d36bc12ba52042a0f980c12ba52042504e8cc12ba5204220f097c12ba5204290e7a3c12ba52042503eb0c12ba52042c0febcc12ba520429034cac12ba5204280ecd7c12ba520421035e6c12ba52042401ef5c12ba52042305d02c22ba52042f08e0ac22ba52042303013c22ba52042604e1cc22ba52042e8f825c22ba52042d04130c22ba52042f83d3bc22ba52042f80547c22ba52042e8b653c22ba520425c7361c22ba52042006570c22ba520422c5f80c22ba52042ae5e89c22ba52042685793c22ba5204284799ec22ba520425402abc22ba520422041b9c22ba52042389ec9c22ba52042c0a5dcc22ba520429a18f3c22ba52042bb0307c32ba52042bd8017c32ba5204253332cc32aa52042",
	},
	{
		"name": "outside, along the front wall",
		"facing": Vector2(-0.479627, -0.877472),
		"cone": "230000004200000000000000000000006afe5cc32866c4c13a6a2dc32966c4c1767a0ec32966c4c10cae0ac3d09ee1c10cae0ac3234002c20cae55c300f263c20cae55c370a37fc20cae55c3a6ea8dc20cae55c3394c9cc20cae55c381ffaac20cae55c33f0ebac20cae55c30983c9c20cae55c36869d9c20cae55c3facde9c20cae55c3a3befac2cc6b1cc22a66c4c12e7912c22966c4c1c26009c22966c4c1f30301c22a66c4c11093f2c12966c4c10a39e4c12966c4c19ad6d6c12966c4c1f44dcac12966c4c1b885bec12966c4c11c68b3c12966c4c158e2a8c12966c4c118e49ec12966c4c1185f95c12966c4c1d8468cc12966c4c1549083c12966c4c1606376c12966c4c1784466c12a66c4c138b456c12966c4c198a447c12966c4c1c80839c12966c4c138d52ac12966c4c150ff1cc12966c4c1607d0fc12966c4c1704602c12966c4c150a4eac02966c4c19031d1c02966c4c12026b8c02966c4c140749fc02966c4c1f00e87c02966c4c160d35dc02966c4c140f12dc02966c4c180c0fcbf2966c4c1c0139ebf2966c4c100c1febe2966c4c100b0743e2966c4c100d5793f2966c4c18078db3f2a66c4c120361d402966c4c120f94c402a66c4c1601c7d402a66c4c1a0db96402966c4c13071af402966c4c1a05bc8402a66c4c180a8e1402966c4c10066fb402966c4c1a0d10a412a66c4c1403818412966c4c198ef25412966c4c1180134412966c4c1107742412966c4c1",
	},
]


## A stand-in for the NPC's body: where it stands and faces.
class Body extends Node2D:
	var facing := Vector2.RIGHT
	var is_dead := false


## A stand-in for the NPC's controller: the overlay's reads, its sight answering the cone's rays with the captured ends in order and
## the bubble's with no wall.
class Eyes extends Node:
	var awareness_radius := AWARENESS
	var view_distance := VIEW
	var fov_degrees := 110.0
	var vision_enabled := true
	var ends := PackedVector2Array()  ## The cone's ray ends, in the order the overlay casts them.
	var _next := 0

	func debug_sight_end(to: Vector2) -> Vector2:
		var body := get_parent() as Node2D
		if absf(to.distance_to(body.global_position) - VIEW) > 1.0:
			return to
		var end := body.global_position + ends[_next % ends.size()]
		_next += 1
		return end


func describe() -> Dictionary:
	return {
		"name": "The vision overlay draws a view cone that lies along a wall",
		"description": "An NPC's view cone whose ray ends run along a straight wall (float noise, which the engine's own polygon cut rejects) is drawn whole: no logged error, the triangles covering the cone's and the bubble's area.",
		"tags": ["ai", "debug", "overlay", "vision"],
		"timeout": 5.0,
	}


func configure(_s: TestSetup) -> void:
	pass


func run(t: TestContext) -> void:
	for pose in POSES:
		var cone: PackedVector2Array = bytes_to_var(String(pose["cone"]).hex_decode())
		t.check(cone.size() == 66 and Geometry2D.triangulate_polygon(cone).is_empty(),
			"%s: the engine's own cut of the captured cone fails (the premise: %d points)" % [pose["name"], cone.size()])
		var body := Body.new()
		body.name = "Body"
		body.top_level = true  # At the origin whatever the world's transform: the overlay's frame is the world's.
		body.facing = pose["facing"]
		var eyes := Eyes.new()
		eyes.name = "GoalController"
		eyes.ends = cone.slice(1)
		body.add_child(eyes)
		var overlay: Node2D = load(VISION_SCRIPT).new()
		overlay.name = "VisionDebug"
		body.add_child(overlay)
		t.world.add_child(body)
		await t.frames(3)
		if not t.require(overlay.has_method("drawn"), "the overlay tells what it drew (drawn())"):
			return
		var drawn: Array = overlay.drawn()
		var bubble := PackedVector2Array()
		for i in 48:
			bubble.append(Vector2.from_angle(TAU * i / 48.0) * AWARENESS)
		for want in [[&"cone", cone], [&"bubble", bubble]]:
			var area := -1.0
			for d in drawn:
				if d["kind"] == want[0]:
					area = _fan_area(d["points"], d["indices"])
			var polygon := absf(_signed_area(want[1]))
			t.check(absf(area - polygon) <= 1.0, "%s: the %s's triangles cover its area (%.1f px², drawn %.1f)"
				% [pose["name"], want[0], polygon, area])
		body.queue_free()
		await t.frames(1)


## The summed area of the triangles `indices` cuts from `points`.
static func _fan_area(points: PackedVector2Array, indices: PackedInt32Array) -> float:
	var total := 0.0
	for k in range(0, indices.size() - 2, 3):
		var a := points[indices[k]]
		total += absf((points[indices[k + 1]] - a).cross(points[indices[k + 2]] - a)) * 0.5
	return total


## The shoelace area of `poly` (signed by its winding).
static func _signed_area(poly: PackedVector2Array) -> float:
	var twice := 0.0
	for k in poly.size():
		twice += poly[k].cross(poly[(k + 1) % poly.size()])
	return twice * 0.5
