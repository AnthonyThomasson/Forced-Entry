extends GameTest
## LD11 (`docs/leadership.md`): the command menu (`scenes/ui/command/command_menu.gd`,
## `PROCESS_MODE_ALWAYS`). Right-click (`Keybinds.COMMAND`, right mouse by default) pauses the tree
## and opens a menu on what is under the cursor, hit-tested from plain dicts:
## - a doorway: "Stack into the <room> (quiet)" and "Stack into the <room> with stun", the second
##   greyed when no recipient carries a stun (D1, `Character.inventory.item_count(STUN_SLOT)`);
## - a room: "Defend the <room>";
## - a teammate: select or deselect it;
## - "Cancel order" when a selected member has one;
## - a ticked list of teammates.
## No selection means the whole squad. Choosing an order emits `order_requested`
## (`{ kind, to, pos | room, bang }`: the click itself; the squad, not the UI, works out the
## doorway's side and room) and closes the menu; Escape closes it too; closing unpauses.
##
## Plain dicts and a fake squad: the Terrace house's `rooms` (as Main hands them,
## `WorldGen.get_rooms`), two teammate puppets and a `view()` callable standing in for the squad's;
## the doorway under a click is the squad's to resolve (`resolve`), so that one callable is a real
## squad's, built over the house the way Main builds it. The menu holds no AI reference; it reads
## its teammates through the Character API only. What it offers is read with `items()`
## (`[{ label, disabled }]`), and an item is chosen the way a click does (pressing the control that
## shows it).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const OrderMenu := preload("res://tests/_ai/order_menu_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
## In the kitchen, clear of every doorway and teammate.
const IN_KITCHEN := Vector2(640, 90)
## In the living room by the living room / kitchen doorway (`door_480_150`), within its width: its
## living room side.
const LIVING_SIDE := Vector2(455, 150)

## The fake squad's view, as the menu's `view` callable returns it.
var _view := {}


func describe() -> Dictionary:
	return {
		"name": "The command menu offers the right orders and works while paused",
		"description": "On a doorway, a room and a teammate the menu offers the right items (stun "
			+ "greyed with no stun), emits the right order_requested for the selection or the "
			+ "whole squad, cancels a selected member's order, pauses the tree and unpauses on "
			+ "close (LD11); and part 2's frag item, Hold for my go, Go on a held door and "
			+ "Ambush, with their requests (LD16).",
		"tags": ["ui", "hud", "leadership", "order"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.lock_interaction([&"camera", &"pause"])
	s.actor(&"t1", &"puppet", Vector2(960, 330), { "faction": &"invader" })
	s.actor(&"t2", &"puppet", Vector2(1000, 420), { "faction": &"invader" })
	s.actor(&"me", &"puppet", Vector2(1100, 500), { "faction": &"invader" })
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	# The clicks below are aimed on a player's screen, headless too, so the menu's panel stands
	# where a person would see it.
	OrderMenu.player_screen(t)
	_keybind(t)
	var menu := _premise_menu(t)
	if menu == null:
		return
	var t1 := t.actor(&"t1")
	var t2 := t.actor(&"t2")
	_view = {
		"leader": t.actor(&"me"),
		"members": [
			{ "node": t1, "order": {}, "step": "" },
			{ "node": t2, "order": {}, "step": "" },
			{ "node": t.actor(&"me"), "order": {}, "step": "" },
		],
	}
	var squad: Node = t.world.squad(&"invader")
	if not t.require(
			squad != null and squad.has_method("resolve"),
			"the squad resolves a click (%s resolve)" % Order.SQUAD_SCRIPT,
	):
		return
	menu.setup({ "camera": t.world.get_viewport().get_camera_2d(), "rooms": t.rooms,
		"teammates": [t1, t2], "view": func(): return _view, "resolve": squad.resolve })
	var got: Array = []
	menu.order_requested.connect(func(d): got.append(d))
	await _check_doorway(t, menu, got, t1, t2)
	await _check_stun_carried(t, menu, got, t1, t2)
	await _check_room(t, menu, got, t1, t2)
	await _check_select(t, menu, got, t1)
	await _check_cancel(t, menu, got, t1)
	await _check_deselect(t, menu, got, t1, t2)
	await _check_tick_and_escape(t, menu, got, t2)
	if not await _check_clicks(t, menu, got, t1, t2):
		return
	await _part_two(t, menu, got, t1, t2)
	t.world.get_tree().paused = false


## The command menu, built, with setup, open_at, items and order_requested, running while the tree
## is paused; null when a premise failed (the test ended).
func _premise_menu(t: TestContext) -> Node:
	var menu := OrderMenu.command_menu(t)
	if not t.require(
			menu != null,
			"the command menu script exists (%s)" % OrderMenu.COMMAND_MENU_SCRIPT,
	):
		return null
	if not t.require(
			menu.has_method("setup")
				and menu.has_method("open_at")
				and menu.has_method("items")
				and menu.has_signal("order_requested"),
			"it has setup, open_at, items and order_requested",
	):
		return null
	t.expect_eq(
		menu.process_mode,
		Node.PROCESS_MODE_ALWAYS,
		"it runs while the tree is paused (PROCESS_MODE_ALWAYS)",
	)
	return menu


## A doorway, nothing selected (the whole squad: `t1`, `t2`), no stun carried: both stack items, the
## stun one greyed; choosing the quiet one while paused emits its request (into `got`) and closes
## the menu.
func _check_doorway(t: TestContext, menu: Node, got: Array, t1: Node, t2: Node) -> void:
	var tree := t.world.get_tree()
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	t.check(tree.paused, "opening the menu pauses the tree")
	var quiet := OrderMenu.item(menu, "Stack into the kitchen (quiet)")
	var stun := OrderMenu.item(menu, "Stack into the kitchen with stun")
	t.check(
		not quiet.is_empty() and not bool(quiet.get("disabled", false)),
		"a doorway offers \"Stack into the kitchen (quiet)\" (items %s)"
			% str(OrderMenu.labels(menu)),
	)
	t.check(
		not stun.is_empty() and bool(stun.get("disabled", false)),
		"and \"Stack into the kitchen with stun\", greyed: no recipient carries a stun",
	)
	t.check(OrderMenu.item(menu, "Defend").is_empty(), "a doorway offers no defend item")
	t.check(
		OrderMenu.choose(menu, "Stack into the kitchen (quiet)"),
		"the quiet stack item can be chosen while paused",
	)
	await t.frames(1)
	if t.check(got.size() == 1, "choosing it emits order_requested"):
		_expect_order(t, got[0], "stack", [t1, t2], "the quiet stack to the whole squad")
		t.check(
			(got[0].get("pos", Vector2.INF) as Vector2).is_equal_approx(Order.BACK_SOUTH),
			"carrying the click (%s)" % str(got[0].get("pos")),
		)
		t.expect_eq(got[0].get("bang"), false, "quiet")
	t.check(not tree.paused, "choosing an order closes the menu and unpauses")
	t.check(OrderMenu.items(menu).is_empty(), "and the menu offers nothing once closed")


## A stun carried by one teammate (`t2`): the stun item is offered for the squad.
func _check_stun_carried(t: TestContext, menu: Node, got: Array, t1: Node, t2: Node) -> void:
	Probe.arm(t2, 1, 0)
	menu.open_at(Order.BACK_ON)
	await t.frames(1)
	t.check(
		not bool(OrderMenu.item(menu, "with stun").get("disabled", true)),
		"with a stun in the squad, \"with stun\" is offered",
	)
	OrderMenu.choose(menu, "Stack into the kitchen with stun")
	await t.frames(1)
	if t.check(got.size() == 2, "choosing it emits order_requested"):
		_expect_order(t, got[1], "stack", [t1, t2], "the stun stack to the whole squad")
		t.expect_eq(got[1].get("bang"), true, "with a stun")
		t.check(
			(got[1].get("pos", Vector2.INF) as Vector2).is_equal_approx(Order.BACK_ON),
			"carrying the click on the opening (%s)" % str(got[1].get("pos")),
		)


## A room offers its defend item and no stack item; the defend order goes to the whole squad.
func _check_room(t: TestContext, menu: Node, got: Array, t1: Node, t2: Node) -> void:
	menu.open_at(IN_KITCHEN)
	await t.frames(1)
	t.check(
		not OrderMenu.item(menu, "Defend the kitchen").is_empty(),
		"a room offers \"Defend the kitchen\" (items %s)" % str(OrderMenu.labels(menu)),
	)
	t.check(OrderMenu.item(menu, "Stack into").is_empty(), "and no stack item")
	OrderMenu.choose(menu, "Defend the kitchen")
	await t.frames(1)
	if t.check(got.size() == 3, "choosing it emits order_requested"):
		_expect_order(t, got[2], "defend_room", [t1, t2], "the defend order to the whole squad")
		t.expect_eq(String(got[2].get("room", "")), "kitchen", "for the kitchen")


## A teammate (`t1`): select it; the next order goes to it alone, and the stun is greyed again (it
## carries none).
func _check_select(t: TestContext, menu: Node, got: Array, t1: Node) -> void:
	menu.open_at(t1.global_position)
	await t.frames(1)
	var select := _named(menu, "select", t1)
	t.check(
		not select.is_empty()
			and not String(select.get("label", "")).to_lower().begins_with("deselect"),
		"a teammate offers to select it (items %s)" % str(OrderMenu.labels(menu)),
	)
	OrderMenu.choose(menu, String(select.get("label", "Select")))
	await t.frames(1)
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	t.check(
		bool(OrderMenu.item(menu, "with stun").get("disabled", false)),
		"with only t1 (no stun) selected, \"with stun\" is greyed",
	)
	t.check(
		OrderMenu.item(menu, "Cancel order").is_empty(),
		"no \"Cancel order\" while no selected member has an order",
	)
	OrderMenu.choose(menu, "Stack into the kitchen (quiet)")
	await t.frames(1)
	if t.check(got.size() == 4, "choosing it emits order_requested"):
		_expect_order(t, got[3], "stack", [t1], "the order to the selected teammate only")


## A selected member (`t1`) with an order: "Cancel order".
func _check_cancel(t: TestContext, menu: Node, got: Array, t1: Node) -> void:
	_view["members"][0]["order"] = { "id": "o1", "kind": "defend_room", "room": "kitchen" }
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	t.check(
		not OrderMenu.item(menu, "Cancel order").is_empty(),
		"\"Cancel order\" when a selected member has one (items %s)" % str(OrderMenu.labels(menu)),
	)
	OrderMenu.choose(menu, "Cancel order")
	await t.frames(1)
	if t.check(got.size() == 5, "choosing it emits order_requested"):
		_expect_order(t, got[4], "cancel", [t1], "the cancel for the selected member")


## Deselect `t1`: the whole squad again.
func _check_deselect(t: TestContext, menu: Node, got: Array, t1: Node, t2: Node) -> void:
	menu.open_at(t1.global_position)
	await t.frames(1)
	var deselect := _named(menu, "deselect", t1)
	t.check(
		not deselect.is_empty(),
		"a selected teammate offers to deselect it (items %s)" % str(OrderMenu.labels(menu)),
	)
	OrderMenu.choose(menu, String(deselect.get("label", "Deselect")))
	await t.frames(1)
	menu.open_at(IN_KITCHEN)
	await t.frames(1)
	OrderMenu.choose(menu, "Defend the kitchen")
	await t.frames(1)
	if t.check(got.size() == 6, "choosing it emits order_requested"):
		_expect_order(
			t,
			got[5],
			"defend_room",
			[t1, t2],
			"deselected, the order goes to the whole squad",
		)


## The ticked list: tick `t2`, the order goes to it; then Escape closes the menu without an order,
## and closing unpauses.
func _check_tick_and_escape(t: TestContext, menu: Node, got: Array, t2: Node) -> void:
	var tree := t.world.get_tree()
	menu.open_at(IN_KITCHEN)
	await t.frames(1)
	t.check(
		OrderMenu.tick(menu, String(t2.name), true),
		"the menu lists the teammates to tick (a checkbox named %s)" % t2.name,
	)
	OrderMenu.choose(menu, "Defend the kitchen")
	await t.frames(1)
	if t.check(got.size() == 7, "choosing it emits order_requested"):
		_expect_order(t, got[6], "defend_room", [t2], "the order to the ticked teammate")

	# Escape closes it without an order; closing unpauses.
	menu.open_at(IN_KITCHEN)
	await t.frames(1)
	_key(KEY_ESCAPE)
	await t.frames(2)
	t.check(
		not tree.paused and OrderMenu.items(menu).is_empty(),
		"Escape closes the menu and unpauses",
	)
	t.expect_eq(got.size(), 7, "with no order")


## Right-click opens it on what is under the cursor; a left-click on a teammate's body (`t1`)
## toggles it while paused. The premise of a click: the view holds still. The runner's camera eases
## in from where the previous test left it (and on while paused), and an injected click is handled
## a frame after it is aimed, so a moving view puts it somewhere else. False when the view never
## held still (the tree unpaused, the test ended).
func _check_clicks(t: TestContext, menu: Node, got: Array, t1: Node, t2: Node) -> bool:
	var tree := t.world.get_tree()
	if not t.require(await OrderMenu.view_still(t), "the view holds still before the clicks"):
		tree.paused = false
		return false
	OrderMenu.click(t, Order.BACK_SOUTH, MOUSE_BUTTON_RIGHT)
	await t.frames(2)
	t.check(
		tree.paused and not OrderMenu.item(menu, "Stack into the kitchen").is_empty(),
		"a right-click on the doorway opens the menu on it (paused %s, items %s)"
			% [str(tree.paused), str(OrderMenu.labels(menu))],
	)
	OrderMenu.click(t, t1.global_position, MOUSE_BUTTON_LEFT)
	await t.frames(2)
	OrderMenu.choose(menu, "Stack into the kitchen (quiet)")
	await t.frames(1)
	if t.check(got.size() == 8, "choosing it emits order_requested"):
		_expect_order(
			t,
			got[7],
			"stack",
			[t1, t2],
			"a left-click on t1's body while paused added it to the selection (t2 was ticked)",
		)
	tree.paused = false
	return true


## LD16 (`docs/leadership.md`, part 2): on a doorway the menu also offers "... with frag" (greyed
## while no recipient carries a frag, as the stun), a panel checkbox "Hold for my go" (off by
## default, remembered while the match runs, D19) that sets `wait_go` on the stack chosen, "Go into
## the <room>" while a member of the view holds a held stack there (whatever the selection, D13),
## and "Ambush the doorway from the <room>" (`<room>` the click side's, as the squad resolves it).
## The requests: `{ kind: "stack", to, pos, bang, mode, wait_go }` (`bang` = mode != quiet, kept for
## part 1), `{ kind: "go", pos }`, `{ kind: "ambush", to, pos }`.
func _part_two(t: TestContext, menu: Node, got: Array, t1: Node, t2: Node) -> void:
	OrderMenu.tick(menu, String(t1.name), false)
	OrderMenu.tick(menu, String(t2.name), false)
	Probe.arm(t1, 0, 0)  # t2 carries the stun it was armed with above, and no frag.
	if not await _check_frag_greyed(t, menu):
		return
	var before := got.size()
	await _check_held_stacks(t, menu, got, before, [t1, t2])
	await _check_go(t, menu, got, t1, before)
	await _check_no_go(t, menu)
	await _check_ambush(t, menu, got, before, [t1, t2])


## On a doorway with no frag carried: the frag item greyed, the ambush item, no Go, and the "Hold
## for my go" checkbox, off by default. False when the checkbox is missing.
func _check_frag_greyed(t: TestContext, menu: Node) -> bool:
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	var frag := OrderMenu.item(menu, "Stack into the kitchen with frag")
	t.check(
		not frag.is_empty() and bool(frag.get("disabled", false)),
		("a doorway offers \"Stack into the kitchen with frag\", greyed: no recipient carries a "
				+ "frag (items %s)") % str(OrderMenu.labels(menu)),
	)
	var ambush := OrderMenu.item(menu, "Ambush the doorway from the kitchen")
	t.check(
		not ambush.is_empty() and not bool(ambush.get("disabled", false)),
		"and \"Ambush the doorway from the kitchen\" (an exterior door: the house's room)",
	)
	t.check(
		OrderMenu.item(menu, "Go into").is_empty(),
		"no \"Go into\" while nobody holds a held stack there",
	)
	var hold := _hold_box(menu)
	if not t.check(hold != null, "the panel has a \"Hold for my go\" checkbox"):
		menu.close()
		return false
	t.check(not hold.button_pressed, "off by default")
	menu.close()
	return true


## A frag carried (by `everyone`'s first): the frag item is offered; with "Hold for my go" ticked
## the stack is held, the box remembered while the match runs (D19); unticked, a stack goes when
## ready. The part's requests are `got` from `before` on.
func _check_held_stacks(
	t: TestContext,
	menu: Node,
	got: Array,
	before: int,
	everyone: Array,
) -> void:
	var t1: Node = everyone[0]
	Probe.arm(t1, 0, 1)
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	t.check(
		not bool(OrderMenu.item(menu, "with frag").get("disabled", true)),
		"with a frag in the squad, \"with frag\" is offered",
	)
	_set_hold(menu, true)
	OrderMenu.choose(menu, "Stack into the kitchen with frag")
	await t.frames(1)
	if t.check(got.size() == before + 1, "choosing it emits order_requested"):
		_expect_stack(t, got[before], StackWant.new("frag", true, everyone), "the held frag stack")
	# D19: remembered while the match runs.
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	t.check(
		_hold_box(menu) != null and _hold_box(menu).button_pressed,
		"\"Hold for my go\" is still ticked when the menu opens again",
	)
	OrderMenu.choose(menu, "Stack into the kitchen (quiet)")
	await t.frames(1)
	if t.check(got.size() == before + 2, "choosing it emits order_requested"):
		_expect_stack(
			t,
			got[before + 1],
			StackWant.new("quiet", true, everyone),
			"the held quiet stack",
		)
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	_set_hold(menu, false)
	OrderMenu.choose(menu, "Stack into the kitchen with stun")
	await t.frames(1)
	if t.check(got.size() == before + 3, "choosing it emits order_requested"):
		_expect_stack(
			t,
			got[before + 2],
			StackWant.new("stun", false, everyone),
			"unticked, a stun stack that goes when ready",
		)


## Go: offered only on a doorway where a member of the view holds a held stack (its view row's
## `held`, at that opening), whatever the selection (only `t1` selected, `t2` holding it); the
## part's requests are `got` from `before` on.
func _check_go(t: TestContext, menu: Node, got: Array, t1: Node, before: int) -> void:
	_view["members"][0]["order"] = {}
	_view["members"][1]["order"] = {
		"id": "o3",
		"kind": "stack",
		"opening": "door_840_190",
		"into": "kitchen",
		"mode": "stun",
		"bang": true,
		"wait_go": true,
		"pos": Vector2(840, 190),
	}
	_view["members"][1]["held"] = true
	OrderMenu.tick(menu, String(t1.name), true)  # Only t1 selected; t2 holds the held stack.
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	var go := OrderMenu.item(menu, "Go into the kitchen")
	t.check(
		not go.is_empty() and not bool(go.get("disabled", false)),
		("\"Go into the kitchen\" on the held stack's doorway, though its holder is not selected "
				+ "(items %s)") % str(OrderMenu.labels(menu)),
	)
	OrderMenu.choose(menu, "Go into the kitchen")
	await t.frames(1)
	if t.check(got.size() == before + 4, "choosing it emits order_requested"):
		t.expect_eq(String(got[before + 3].get("kind", "")), "go", "the go request: kind go")
		t.check(
			(got[before + 3].get("pos", Vector2.INF) as Vector2).is_equal_approx(Order.BACK_SOUTH),
			"carrying the click (%s)" % str(got[before + 3].get("pos")),
		)
	OrderMenu.tick(menu, String(t1.name), false)


## No Go for a stack that goes when ready, nor for a held stack at another doorway.
func _check_no_go(t: TestContext, menu: Node) -> void:
	_view["members"][1]["order"]["wait_go"] = false
	_view["members"][1]["held"] = false
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	t.check(
		OrderMenu.item(menu, "Go into").is_empty(),
		"no \"Go into\" for a stack that goes when ready (items %s)" % str(OrderMenu.labels(menu)),
	)
	menu.close()
	_view["members"][1]["order"]["wait_go"] = true
	_view["members"][1]["held"] = true
	_view["members"][1]["order"]["opening"] = "door_690_360"
	menu.open_at(Order.BACK_SOUTH)
	await t.frames(1)
	t.check(
		OrderMenu.item(menu, "Go into").is_empty(),
		"nor for a held stack at another doorway (items %s)" % str(OrderMenu.labels(menu)),
	)
	_view["members"][1]["order"] = {}
	_view["members"][1]["held"] = false


## Ambush, for the whole squad (`everyone`); by an interior doorway, from the side clicked. The
## part's requests are `got` from `before` on.
func _check_ambush(t: TestContext, menu: Node, got: Array, before: int, everyone: Array) -> void:
	OrderMenu.choose(menu, "Ambush the doorway from the kitchen")
	await t.frames(1)
	if t.check(got.size() == before + 5, "choosing the ambush emits order_requested"):
		_expect_order(t, got[before + 4], "ambush", everyone, "the ambush to the whole squad")
		t.check(
			(got[before + 4].get("pos", Vector2.INF) as Vector2).is_equal_approx(Order.BACK_SOUTH),
			"carrying the click (%s)" % str(got[before + 4].get("pos")),
		)
	# An interior doorway clicked from the living room's side: the ambush is from the living room,
	# the stack into the kitchen.
	menu.open_at(LIVING_SIDE)
	await t.frames(1)
	t.check(
		not OrderMenu.item(menu, "Ambush the doorway from the living room").is_empty(),
		("by the living room / kitchen doorway, from the living room's side: \"Ambush the doorway "
				+ "from the living room\" (items %s)") % str(OrderMenu.labels(menu)),
	)
	t.check(
		not OrderMenu.item(menu, "Stack into the kitchen").is_empty(),
		"beside \"Stack into the kitchen\"",
	)
	menu.close()


## The panel's "Hold for my go" checkbox, or null.
func _hold_box(menu: Node) -> BaseButton:
	for box: BaseButton in menu.find_children("*", "BaseButton", true, false):
		if ((box is CheckBox or box is CheckButton)
				and String(box.text).to_lower().contains("hold for my go")):
			return box
	return null


## Tick or untick "Hold for my go" the way a click does.
func _set_hold(menu: Node, on: bool) -> void:
	var box := _hold_box(menu)
	if box != null and box.button_pressed != on:
		box.button_pressed = on
		box.toggled.emit(on)


## Check an emitted stack request of part 2: its recipients, `mode`, `wait_go` and part 1's `bang`
## (mode != quiet).
func _expect_stack(t: TestContext, request: Dictionary, want: StackWant, what: String) -> void:
	_expect_order(t, request, "stack", want.to, what)
	t.expect_eq(String(request.get("mode", "")), want.mode, "%s: mode %s" % [what, want.mode])
	t.expect_eq(
		request.get("wait_go"),
		want.wait_go,
		"%s: wait_go %s" % [what, str(want.wait_go)],
	)
	t.expect_eq(
		request.get("bang"),
		want.mode != "quiet",
		"%s: bang %s (mode != quiet)" % [what, str(want.mode != "quiet")],
	)


## `Keybinds.COMMAND` ("command"): right mouse by default, with a settings label and group (read by
## name: the action may not exist yet).
func _keybind(t: TestContext) -> void:
	var consts: Dictionary = (Keybinds.get_script() as Script).get_script_constant_map()
	var action = consts.get("COMMAND")
	if not t.check(action != null, "Keybinds has a COMMAND action"):
		return
	t.expect_eq(String(action), "command", "named \"command\"")
	var mouse: Dictionary = consts.get("MOUSE_DEFAULTS", {})
	t.expect_eq(mouse.get(action), MOUSE_BUTTON_RIGHT, "right mouse by default")
	t.expect_eq(
		String(consts.get("LABELS", {}).get(action, "")),
		"Command teammates",
		"labelled \"Command teammates\" on the settings page",
	)
	t.check(consts.get("GROUPS", {}).has(action), "in a settings group")


## The offered item whose label contains `verb` and the name of `who` (case-insensitive), or {}.
func _named(menu: Node, verb: String, who: Node) -> Dictionary:
	for i in OrderMenu.items(menu):
		var label := String(i.get("label", "")).to_lower()
		if label.contains(verb) and label.contains(String(who.name).to_lower()):
			return i
	return {}


## Check an emitted order request: its kind and its recipients (`to`, as a set).
func _expect_order(
	t: TestContext,
	request: Dictionary,
	kind: String,
	to: Array,
	what: String,
) -> void:
	t.expect_eq(String(request.get("kind", "")), kind, "%s: kind %s" % [what, kind])
	var names := func(nodes: Array) -> Array:
		var out := nodes.map(func(n): return String(n.name) if n is Node else str(n))
		out.sort()
		return out
	t.expect_eq(
		names.call(request.get("to", [])),
		names.call(to),
		"%s: to %s" % [what, str(names.call(to))],
	)


## Press and release `key` as the test's own input.
func _key(key: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = pressed
		TestContext.inject(ev)


## The stack request part 2 expects: its `mode`, its `wait_go` and its recipients `to`.
class StackWant extends RefCounted:
	## quiet / stun / frag.
	var mode: String
	## Whether it waits for the leader's go.
	var wait_go: bool
	## The recipients, as a set.
	var to: Array

	func _init(want_mode: String, want_wait_go: bool, want_to: Array) -> void:
		mode = want_mode
		wait_go = want_wait_go
		to = want_to
