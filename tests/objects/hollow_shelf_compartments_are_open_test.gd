extends GameTest
## An emptied shelf is hollow (#194, D21, `docs/stacked-items.md` SI13): a ray flown level
## from the front of a bare shelving between its boards gets in and meets its back (a round and a
## line of sight go into the compartment), at a board's height it meets the board's front lip, and
## over the boards of its top compartment (it has no top board) it meets the back; the same
## shelving built solid (the old look) stops all three at the front. A ray along the shelf's width
## meets a side, at every height: the sides are whole.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const ShelfMesh := preload("res://scenes/objects/art/shelf_mesh.gd")
const SOLID_AT := Vector2(250, 250)
const HOLLOW_AT := Vector2(550, 250)
## A height in the shelving's lowest compartment (the board tops are 2, 27, 52), at the second
## board (25 to 27), and over the third board (54 to 77: the top compartment).
const BETWEEN := 14.0
const AT_BOARD := 26.0
const OVER := 70.0
## How far (px) a front or back hit may be off its edge.
const EDGE := 2.5


func describe() -> Dictionary:
	return {
		"name": "A hollow shelf's compartments are open to a ray",
		"description": "Bare shelving: a level ray between its boards reaches its back, at a "
			+ "board it meets the front lip, over the third board it reaches the back (no top "
			+ "board); a solid shelving meets the front at all of them; along the width a side "
			+ "stops it at every height.",
		"tags": ["furniture", "3d", "items", "sight", "unbake"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	var solid := WorldGen.object_definition("shelving").duplicate(true)
	var opts: Dictionary = solid.get("art_opts", {})
	opts["loose"] = false
	solid["art_opts"] = opts
	s.object(&"solid", solid, SOLID_AT)
	s.object(&"hollow", "shelving", HOLLOW_AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	for id: StringName in [&"solid", &"hollow"]:
		_front_and_back(t, id, t.object(id) as Node2D)
		_sides(t, id, t.object(id) as Node2D)


## The rays from the front of `shelf` (`id`): open to the back, or stopped at the front.
func _front_and_back(t: TestContext, id: StringName, shelf: Node2D) -> void:
	var open := id == &"hollow"
	var size: Vector2 = shelf.size
	var front: float = shelf.position.y + size.y * 0.5
	var back: float = shelf.position.y - size.y * 0.5
	for height: float in [BETWEEN, OVER]:
		var hit := _from_front(t, shelf, height)
		t.require(not hit.is_empty(), "%s: a ray at %.0f px meets the shelf" % [id, height])
		var at: float = PlanSpace.plan_of(hit["position"]).y
		if open:
			t.check(
				at < back + ShelfMesh.HULL + EDGE, "%s: at %.0f px it reaches the back (%.1f)" % [
					id,
					height,
					at,
				]
			)
		else:
			t.check(
				at > front - EDGE,
				"%s: at %.0f px it stops at the front (%.1f)" % [id, height, at],
			)
	var lip := _from_front(t, shelf, AT_BOARD)
	var lip_at: float = PlanSpace.plan_of(lip["position"]).y
	t.check(
		lip_at > front - EDGE, "%s: at a board it meets the front lip (%.1f)" % [id, lip_at]
	)


## The rays along the width of `shelf` (`id`): a side stops each, at every height.
func _sides(t: TestContext, id: StringName, shelf: Node2D) -> void:
	for height: float in [BETWEEN, AT_BOARD, OVER]:
		var side := Probe.ray_level(
			t,
			Vector2(shelf.position.x - shelf.size.x, shelf.position.y),
			Vector2(shelf.position.x, shelf.position.y),
			height,
		)
		var at_x: float = PlanSpace.plan_of(side["position"]).x if not side.is_empty() else INF
		t.check(
			absf(at_x - (shelf.position.x - shelf.size.x * 0.5)) < EDGE,
			"%s: along the width at %.0f px a side stops it (%.1f)" % [id, height, at_x],
		)


## The first hit of a ray flown level at `height` from in front of `shelf` to behind it.
func _from_front(t: TestContext, shelf: Node2D, height: float) -> Dictionary:
	return Probe.ray_level(
		t,
		Vector2(shelf.position.x, shelf.position.y + shelf.size.y),
		Vector2(shelf.position.x, shelf.position.y - shelf.size.y),
		height,
	)
