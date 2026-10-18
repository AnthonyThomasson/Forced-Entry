extends GameTest

## D4 / E18 (`docs/leadership.md`, `docs/tactical-entry.md`): an approach never runs through the room being entered. The Terrace house
## (furnished), one invader in the back garden ordered (quiet, held for the go) to stack on the hall door into the kitchen, on its west
## side. The way to its slot that keeps out of only that doorway's view runs in at the back door, across the kitchen and out by the living
## room, so only the kitchen's floor carved into the avoid map (`AgentDoorViews._with_room`, asked for by `walk_route` once the uncarved way
## round goes into the room) keeps the approach out of it: round the house and in at the front door. The member must reach its slot without
## ever standing in the kitchen. The test first measures, on avoid maps of its own, that the way round the doorway's view alone does go
## through the kitchen and that a way round both exists (`reach_probe.gd` `keep_out_route`; on the east side none does, and the walk goes
## the plain way, E18).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Reach := preload("res://tests/_ai/reach_probe.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")

## How long (sim s) the member has to reach its slot.
const WATCH_CAP := 60.0
## How far (px) inside the kitchen's rect a point must lie to count as in it (a point on the wall line does not).
const INSET := 2.0


func describe() -> Dictionary:
	return {
		"name": "An ordered approach whose way round the doorway's view crosses the room being entered goes round that room",
		"description": "An invader in the back garden ordered to stack on the west side of the Terrace hall door into the kitchen reaches its slot without walking through the kitchen, though the way round the doorway's view alone runs through it (D4, E18).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, true)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"outside", &"invader", Vector2(1000, 300), { "max_health": 1000000.0 })
	s.actor(&"lead", &"puppet", Vector2(1400, 800), { "faction": &"invader", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	var f := Reach.frame(t, Maps.DOOR_HALL_KITCHEN, "kitchen")
	if not t.require(not f.is_empty(), "the doorway is in the house (test set-up)"):
		return
	var squad := Order.raid(t, [&"outside"], &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.3)
	var member: Node2D = t.actor(&"outside")
	var start: Vector2 = member.global_position
	var order := Order.stack_order(squad, [member], Reach.click(f, -1), "quiet", true)
	if not t.require(not order.is_empty(), "the squad posts the stack order on %s (issue)" % f["id"]):
		return
	var kitchen: Rect2 = (f["room"] as Rect2).grow(-INSET)
	var spot := Vector2.INF
	var in_kitchen: Array = []   # [t, pos] the first time it stood in the kitchen
	var reached := INF
	var t0 := t.time
	while t.time - t0 < WATCH_CAP:
		var e := Entry.entry(Entry.brain(t, &"outside"))
		var at: Variant = e.get("stack_point", Vector2.INF)
		if String(e.get("opening", "")) == String(f["id"]) and at is Vector2 and at != Vector2.INF:
			spot = at
		if in_kitchen.is_empty() and kitchen.has_point(member.global_position):
			in_kitchen = [t.time - t0, member.global_position]
		if spot != Vector2.INF and String(e.get("phase", "")) == "stack" and member.global_position.distance_to(spot) <= Reach.SLOT_REACH:
			reached = t.time - t0
			break
		await t.frames(1)
	if not t.require(spot != Vector2.INF, "the member claims a slot at %s" % f["id"]):
		return
	var through := await _view_only_route_crosses(t, f, start, spot)
	if not t.require(through == "", "set-up: the way round the doorway's view alone, from the garden to the slot, runs through the kitchen (%s)" % through):
		return
	var round_both: Dictionary = await Reach.keep_out_route(t, f, start, spot, t.world.get_world_2d().navigation_map)
	if not t.require(round_both.has("path"), "set-up: a way from the garden to the slot keeps out of both the kitchen and the doorway's view (%s)" % round_both.get("why", "")):
		return
	t.check(reached != INF, "the member reaches its slot at %s within %.0f s (%s)" % [spot, WATCH_CAP, "at %.1f s" % reached if reached != INF else "never"])
	t.check(in_kitchen.is_empty(), "the member never stands in the kitchen on its approach (%s)" % [
			"in it at %.1f s at %s" % in_kitchen if not in_kitchen.is_empty() else "never in it"])


## "" when the route from `from` to `to` on an avoid map with only the doorway's view carved (the test's own polygon) runs through the
## kitchen; else why not, in words.
func _view_only_route_crosses(t: TestContext, f: Dictionary, from: Vector2, to: Vector2) -> String:
	var map: RID = t.world.get_world_2d().navigation_map
	var region := NavBuilder.planning_region(map)
	if region == null:
		return "no planning region to measure on"
	var avoid := NavBuilder.avoid_map(region, "keep_out_test_view_%s" % f["id"], [View.polygon(f)])
	var waited := 0
	while not NavBuilder.ready(avoid) and waited < 240:
		await t.frames(1)
		waited += 1
	if not NavBuilder.ready(avoid):
		return "the avoid map never came up"
	var path := NavBuilder.route(avoid, from, to)
	if path.is_empty():
		return "no route round the view"
	var kitchen: Rect2 = (f["room"] as Rect2).grow(-INSET)
	for i in range(1, path.size()):
		var steps := maxi(int(path[i - 1].distance_to(path[i]) / 8.0), 1)
		for k in steps + 1:
			if kitchen.has_point(path[i - 1].lerp(path[i], float(k) / float(steps))):
				return ""
	return "its %.0f px route keeps out of the kitchen" % NavBuilder.path_length(path)
