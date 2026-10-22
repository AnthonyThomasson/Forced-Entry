extends GameTest
## E18 (`docs/tactical-entry.md`): a doorway's view (`AgentDoorViews.door_view`) is laid out from
## its wedge, and publishing the wedge (`AgentDoorViews.wedge`, ticket #95) changed no view.
## `door_view_unchanged.json` beside this test is a capture of every view of a generated house (the
## garage home, seed 1: every doorway seen from each room it joins), taken before the wedge was
## published: each view must come out the same polygon, point for point, exactly. The capture
## follows the house: a change to the floorplan or the generator that moves a wall or a doorway is
## a new house, to be captured again. The wedge itself is the test's own copy of the rule
## (`tests/_ai/door_view_probe.gd`, `View.polygon`): for every doorway and room, out to the view's
## depth and to another depth.

const View := preload("res://tests/_ai/door_view_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
const DoorViews := preload("res://scenes/ai/perception/agent_door_views.gd")
const CAPTURE := "res://tests/ai/perception/door_view_unchanged.json"
const PLAN := "garage_home"
const SEED := 1
## A second depth (px) the wedge is read at, beside the view's own (`View.DEPTH`).
const OTHER_DEPTH := 200.0


func describe() -> Dictionary:
	return {
		"name": "A doorway's view is unchanged by publishing its wedge",
		"description": "Every view of every doorway of a generated house is, point for point, the "
			+ "polygon captured before the wedge was published, and each wedge is the rule's "
			+ "(E18).",
		"tags": ["ai", "perception", "door_view", "geometry", "regression"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)


func run(t: TestContext) -> void:
	var file := FileAccess.open(CAPTURE, FileAccess.READ)
	if not t.require(file != null, "the capture exists (%s)" % CAPTURE):
		return
	var expected: Dictionary = JSON.parse_string(file.get_as_text())
	var got := _views(t)
	t.expect_eq(got.keys(), expected.keys(), "the same views (each doorway from each room)")
	for key: String in expected:
		if not got.has(key):
			continue
		var was := _polygon(expected[key])
		t.check(
			got[key] == was,
			"the view %s is the captured polygon (%s; captured %s)" % [key, got[key], was],
		)
	for o: Dictionary in t.world.openings:
		for k in o.get("rooms", []):
			var f := Slots.frame(o, String(k), t.rooms)
			for depth in [View.DEPTH, OTHER_DEPTH]:
				var want := View.polygon(f, depth)
				var wedge := DoorViews.wedge(o, f["room"], depth)
				t.check(
					_same(wedge, want),
					"the wedge of %s from %s, %.0f px deep, is the rule's (%s; the rule's %s)"
						% [f["id"], k, depth, wedge, want],
				)


## Every view of the house: "<opening id>><room key>" -> its polygon, in the openings' order.
func _views(t: TestContext) -> Dictionary:
	var views := DoorViews.new()
	views.set_house(t.world.openings, t.rooms)
	var w2d := t.world.get_world_2d()
	var out := {}
	for o: Dictionary in t.world.openings:
		var id := DoorViews.opening_id(o)
		for k in o.get("rooms", []):
			out["%s>%s" % [id, k]] = views.door_view(
				id,
				String(k),
				w2d.navigation_map,
				w2d.direct_space_state,
			)
	return out


## The polygon a capture holds (`[[x, y], ...]`).
func _polygon(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in points:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## Whether polygons `a` and `b` have the same points, each within float rounding.
func _same(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true
