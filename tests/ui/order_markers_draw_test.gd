extends GameTest
## LD12 / D5 (`docs/leadership.md`): the order markers (`scenes/ui/hud/order_markers.gd`,
## `OrderMarkers`, drawn at `DrawLayers.ABOVE`), built only when the human leads. A marker on each
## member's order target and the selection highlight (who leads is the squad-leaders debug
## overlay's, `leader_overlay_draw_test.gd`). A decoupled observer: `watch(view_callable)` polls the
## squad's `view()` (`{ leader, members: [{ node, order, step }] }`), `set_selection(nodes)` is the
## menu's selection, and `drawn()` is what is shown (`[{ kind, point, node }]`, `kind` `order` /
## `selected`), which this test reads.
##
## A fake squad view (plain data) over three puppets.

const Order := preload("res://tests/_ai/order_probe.gd")

## The fake squad's view, as the markers' `view` callable returns it.
var _view := {}


func describe() -> Dictionary:
	return {
		"name": "Order markers draw each order and the selection",
		"description": "The markers mark one target per member with an order and none without, and "
			+ "each selected teammate; the leader is not theirs to mark (LD12, D5); part 2's "
			+ "targets are named with the stack's mode and hold, or Ambush (LD16).",
		"tags": ["ui", "hud", "leadership", "order"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.actor(&"me", &"puppet", Vector2(150, 300), { "faction": &"invader" })
	s.actor(&"t1", &"puppet", Vector2(400, 200), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(600, 400), { "faction": &"invader" })


func run(t: TestContext) -> void:
	if not t.require(
			ResourceLoader.exists(Order.ORDER_MARKERS_SCRIPT),
			"the order markers script exists (%s)" % Order.ORDER_MARKERS_SCRIPT,
	):
		return
	var markers: Node2D = (load(Order.ORDER_MARKERS_SCRIPT) as GDScript).new()
	t.world.add_child(markers)
	if not t.require(
			markers.has_method("watch")
				and markers.has_method("set_selection")
				and markers.has_method("drawn"),
			"it has watch, set_selection and drawn",
	):
		return
	t.expect_eq(
		markers.z_index,
		DrawLayers.ABOVE,
		"drawn above the standing world (DrawLayers.ABOVE)",
	)
	var me := t.actor(&"me")
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	_view = _first_view(me, t1, t2)
	markers.watch(func(): return _view)
	await t.frames(2)
	await _check_part_one(t, markers, t1, t2)
	await _part_two(t, markers, t1, t2)


## The squad's first view: `me` leading, `t1` defending the kitchen, `t2` with no order.
func _first_view(me: Node, t1: Node, t2: Node) -> Dictionary:
	return {
		"leader": me,
		"members": [
			{ "node": me, "order": {}, "step": "" },
			{
				"node": t1,
				"order": {
					"id": "o1",
					"kind": "defend_room",
					"room": "kitchen",
					"pos": Vector2(700, 100),
				},
				"step": "moving",
			},
			{ "node": t2, "order": {}, "step": "" },
		],
	}


## No marker on the leader, one order target per member with an order, the selected teammate ringed
## where it stands until the selection is cleared.
func _check_part_one(t: TestContext, markers: Node, t1: Node, t2: Node) -> void:
	t.check(
		_of(markers, "leader").is_empty(),
		"no marker on the leader (the squad-leaders debug overlay's)",
	)
	var orders := _of(markers, "order")
	t.check(
		orders.size() == 1 and orders[0].get("node") == t1,
		"one order target, for the member with an order (%s)" % str(orders),
	)
	t.check(_of(markers, "selected").is_empty(), "no selection drawn while nothing is selected")

	markers.set_selection([t2])
	await t.frames(2)
	var selected := _of(markers, "selected")
	t.check(
		selected.size() == 1
			and (selected[0].get("point", Vector2.INF) as Vector2).distance_to(t2.global_position)
				< 2.0,
		"the selected teammate is highlighted where it stands (%s)" % str(selected),
	)

	_view["members"][2]["order"] = {
		"id": "o2",
		"kind": "stack",
		"opening": "door_840_190",
		"into": "kitchen",
		"mode": "quiet",
		"pos": Vector2(870, 255),
	}
	await t.frames(2)
	t.expect_eq(_of(markers, "order").size(), 2, "a second member's order adds a second target")

	markers.set_selection([])
	await t.frames(2)
	t.check(_of(markers, "selected").is_empty(), "clearing the selection clears its highlight")


## LD16 (`docs/leadership.md`, part 2): the markers name the new order kinds at their targets: a
## stack's mode and whether it is held for go ("Stack (frag, hold) · in position"), and an ambush
## ("Ambush · in position"). A stun stack not held for go reads "Stack (stun)", and a join (LD24)
## "Join stack". The words are read off `drawn()`'s `label`.
func _part_two(t: TestContext, markers: Node, t1: Node, t2: Node) -> void:
	_view["members"][1]["order"] = {
		"id": "o3",
		"kind": "stack",
		"opening": "door_840_190",
		"into": "kitchen",
		"mode": "frag",
		"bang": true,
		"wait_go": true,
		"pos": Vector2(870, 190),
	}
	_view["members"][1]["held"] = true
	_view["members"][1]["step"] = "in_position"
	_view["members"][2]["order"] = {
		"id": "o4",
		"kind": "ambush",
		"opening": "door_150_360",
		"room": "living_room",
		"pos": Vector2(150, 360),
	}
	_view["members"][2]["step"] = "in_position"
	await t.frames(2)
	t.expect_eq(
		_label_for(markers, t1),
		"Stack (frag, hold) · in position",
		"a held frag stack is named with its mode and hold",
	)
	t.expect_eq(_label_for(markers, t2), "Ambush · in position", "an ambush is named Ambush")
	await _check_stun_labels(t, markers, t1)
	await _check_join_label(t, markers, t1)


## A stun stack of `t1` held for go is named with its mode and hold, one not held with its mode
## alone.
func _check_stun_labels(t: TestContext, markers: Node, t1: Node) -> void:
	_view["members"][1]["order"] = {
		"id": "o5",
		"kind": "stack",
		"opening": "door_840_190",
		"into": "kitchen",
		"mode": "stun",
		"bang": true,
		"wait_go": true,
		"pos": Vector2(870, 190),
	}
	_view["members"][1]["step"] = "moving"
	await t.frames(2)
	var stun_hold := _label_for(markers, t1)
	t.check(
		stun_hold.contains("stun") and stun_hold.contains("hold"),
		"a held stun stack is named with its mode and hold (%s)" % stun_hold,
	)
	_view["members"][1]["order"] = {
		"id": "o6",
		"kind": "stack",
		"opening": "door_840_190",
		"into": "kitchen",
		"mode": "stun",
		"bang": true,
		"pos": Vector2(870, 190),
	}
	_view["members"][1]["held"] = false
	await t.frames(2)
	t.expect_eq(
		_label_for(markers, t1),
		"Stack (stun) · moving",
		"a stun stack not held for go is named with its mode alone",
	)


## LD24: the stack a leader's own claim rallies its free followers into (a `stack` order in mode
## `join`) is the member (`t1`) joining the leader's stack, named "Join stack".
func _check_join_label(t: TestContext, markers: Node, t1: Node) -> void:
	_view["members"][1]["order"] = {
		"id": "o7",
		"kind": "stack",
		"opening": "door_840_190",
		"into": "kitchen",
		"mode": "join",
		"bang": false,
		"wait_go": false,
		"split": false,
		"pos": Vector2(870, 190),
	}
	await t.frames(2)
	t.expect_eq(
		_label_for(markers, t1),
		"Join stack · moving",
		"a join order (the leader's stack rallying the member) is named Join stack",
	)


## The label drawn at the order target of `member`, or "".
func _label_for(markers: Node, member: Node) -> String:
	for d in _of(markers, "order"):
		if d.get("node") == member:
			return String(d.get("label", ""))
	return ""


## The drawn markers of `kind`.
func _of(markers: Node, kind: String) -> Array:
	return (markers.drawn() as Array).filter(func(d): return String(d.get("kind", "")) == kind)
