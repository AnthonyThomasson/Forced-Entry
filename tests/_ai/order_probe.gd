extends RefCounted
## Shared helpers for the leadership tests (`docs/leadership.md` LD1 to LD12; not a test itself):
## `const Order := preload("res://tests/_ai/order_probe.gd")`. A squad per side with a leader,
## orders (`defend_room`, `stack`, `cancel`) carried on the `&"order"` bus topic, the ORDER decision
## node, the progress radio (`order_id`, `order_step` on a callout), the pausable AI clock
## (`GameClock`), the command menu and the order markers.
##
## Everything new is reached by path and duck-typed (`ResourceLoader.exists`, `has_method`, `get`),
## so a test loads and runs before the feature exists and goes red on an assertion that names what
## is missing, never on a parse error. The NPC is read only through its controller's public reads:
## `current_act()`, `debug_state()` (the `facts` of its last decision, the running leaf's
## `primitive` and `params`, the levels of its last walk), `debug_entry()`, `debug_memory()`,
## `known_contacts_for_display()` and its radio.

const SQUAD_SCRIPT := "res://scenes/ai/team/squad.gd"
const COMMAND_MENU_SCRIPT := "res://scenes/ui/hud/command_menu.gd"
const ORDER_MARKERS_SCRIPT := "res://scenes/ui/hud/order_markers.gd"
const OVERLAY_TOGGLES_SCRIPT := "res://scenes/ui/overlays/overlay_toggles.gd"
const Entry := preload("res://tests/_ai/entry_probe.gd")
## The order kinds (LD5).
const DEFEND := "defend_room"
const STACK := "stack"
const CANCEL := "cancel"
## The order kinds of part 2 (LD13, LD15): the leader's go for a held stack, and an ambush on a
## doorway.
const GO := "go"
const AMBUSH := "ambush"
## D7: the safety cap (s) on an ordered stack's wait for all its recipients' `ready`.
const ORDER_READY_CAP := 60.0
# --- Stack orders at the Terrace house's back door (LD9) ------------------------------------------
# The back door (`Entry.BACK`: `door_840_190`, 90 px wide, in the kitchen's east wall) and where a
# leader's click on it lands (D3): the side of the wall plane clicked is the side the stack forms
# on; left or right of the opening along the wall picks the stack's side of the door; a click on the
# opening (within its half-width along the wall) is a split stack; an exterior door always goes into
# the house.
## Outside (the back garden), along the wall north of the opening: a stack north of the door, into
## the kitchen.
const BACK_NORTH := Vector2(870, 125)
## Outside, along the wall south of the opening: a stack south of the door, into the kitchen.
const BACK_SOUTH := Vector2(870, 255)
## Outside, on the opening: a split stack, into the kitchen.
const BACK_ON := Vector2(870, 190)
## Inside the kitchen, north of the opening: an exterior door still goes into the house's room.
const BACK_INSIDE_NORTH := Vector2(810, 125)
## The back door's centre y and half-width: north of the door is y < 190 - 45, south y > 190 + 45.
const BACK_Y := 190.0
const BACK_HALF := 45.0
# --- The command menu's panel on screen (LD11) ----------------------------------------------------
## Its gap to the screen edge it docks against (past the overlay bar's column when Debug is on) and
## its least width (screen px).
const PANEL_EDGE := 24.0
const PANEL_WIDTH := 440.0


# --- The squad (LD3, LD4, LD5) --------------------------------------------------------------------


## Build and bind the squad of `faction` over `members` (spawn order, all of that faction) the way
## Main builds a side's (`MatchBuilder.build_squads` under the world, over the test world's house),
## `leader` its human leader or null (no `PlayerStack`). For the squads no setup declares: a test
## with one squad per side declares them (`s.squads`, read with `t.squad`).
static func squad(t: TestContext, faction: StringName, members: Array, leader: Node = null) -> Node:
	var openings: Array = t.world.get("openings") if t.world.get("openings") != null else []
	var human := { "node": leader, "lead": true } if leader != null else {}
	var built := MatchBuilder.build_squads(t.world, members, openings, t.rooms, human)
	return built.get(faction)


## `squad.issue(request)` (`{ kind, to, pos, room, bang }`, what the command menu emits): the order
## it posted, or {} (also when the squad has no `issue` yet).
static func issue(s: Node, request: Dictionary) -> Dictionary:
	if s == null or not s.has_method("issue"):
		return {}
	var out = s.issue(request)
	return out if out is Dictionary else {}


## The squad's `view()` (`{ leader, members: [{ node, order, step }] }`), or {}.
static func view(s: Node) -> Dictionary:
	return s.view() if s != null and s.has_method("view") else {}


## What the squad's view says of `member`: `{ node, order, step }`, or {}.
static func member_view(s: Node, member: Node) -> Dictionary:
	for m in view(s).get("members", []):
		if m.get("node") == member:
			return m
	return {}


## The `&"order"` events posted so far (their data), optionally only those whose `to` names `who`.
static func orders(t: TestContext, who: Node = null) -> Array:
	return t.events_of(&"order", func(d): return who == null or (d.get("to", []) as Array).has(who))


## Post an order straight onto the bus, as a squad does (LD5):
## `{ id, leader, faction, to, kind, ... }`, stamped with the frame it is posted on (`frame`) unless
## it names one.
static func post(order: Dictionary) -> void:
	EventBus.post(&"order", order.merged({ "frame": GameClock.frame() }))


# --- The NPC --------------------------------------------------------------------------------------


## The controller of actor `id`.
static func brain(t: TestContext, id: StringName) -> Node:
	return t.controller(id, &"debug_state")


## Whether the NPC's last decision snapshot had the fact `ordered` (LD5).
static func ordered(b: Node) -> bool:
	return (bool((b.debug_state().get("facts", {}) as Dictionary).get("ordered", false))
			if b != null
			else false)


## How many decision walks the NPC has started.
static func decisions(b: Node) -> int:
	return int(b.debug_state().get("decisions", 0)) if b != null else 0


## The running leaf's primitive (`debug_state()["primitive"]`).
static func primitive(b: Node) -> String:
	return String(b.debug_state().get("primitive", "")) if b != null else ""


## The running leaf's params (`debug_state()["params"]`).
static func params(b: Node) -> Dictionary:
	return b.debug_state().get("params", {}) if b != null else {}


## Whether the NPC is carrying out an order: its decision path starts at the ORDER node (LD6).
static func on_order(b: Node) -> bool:
	return b != null and String(b.current_act()).begins_with("order")


## The levels of the NPC's last decision walk.
static func levels(b: Node) -> Array:
	return b.debug_state().get("decision", {}).get("levels", []) if b != null else []


## Force a decision on the NPC now without touching its brain: gunfire from nobody it knows lands
## beside it (`&"hit"`, no attacker), which it hears as fire at it.
static func gunfire_near(c: Node) -> void:
	EventBus.post(
		&"hit",
		{
			"position": c.global_position + Vector2(40, 0),
			"direction": Vector2.LEFT,
			"damage": 10.0,
			"attacker": null,
			"victim": null,
		},
	)


# --- The radio (LD7) ------------------------------------------------------------------------------


## The callouts that carry an `order_step` (LD7), optionally only step `step` and / or only from
## character `who`.
static func progress(t: TestContext, step := "", who: Node = null) -> Array:
	return t.events_of(&"callout", func(d):
		if String(d.get("order_step", "")) == "":
			return false
		if step != "" and String(d.get("order_step", "")) != step:
			return false
		return who == null or d.get("speaker") == who)


## The entry claims (any entry step) from `who` that carry an `order_id`.
static func ordered_claims(t: TestContext, who: Node, opening := "") -> Array:
	return t.events_of(&"callout", func(d):
		return (d.get("speaker") == who
				and String(d.get("entry_step", "")) != ""
				and str(d.get("order_id", "")) != ""
				and (opening == "" or String(d.get("opening", "")) == opening)))


## The raw callout events (`{ topic, data, time }`) of entry step `step` from `who` (any step when
## ""), oldest first.
static func raw_calls(t: TestContext, who: Node, step := "") -> Array:
	var out: Array = []
	for e: Dictionary in t.events:
		if e["topic"] != &"callout" or e["data"].get("speaker") != who:
			continue
		var s := String(e["data"].get("entry_step", ""))
		if s == "" or (step != "" and s != step):
			continue
		out.append(e)
	return out


## The sim time of the first raw event of `topic` passing `filter`, or INF.
static func first_time(t: TestContext, topic: StringName, filter: Callable) -> float:
	for e: Dictionary in t.events:
		if e["topic"] == topic and filter.call(e["data"]):
			return float(e["time"])
	return INF


# --- The clock (LD1) ------------------------------------------------------------------------------


## Hold the tree paused for `wall_s` seconds of wall time, then unpause. The test's own clock stops
## with the world (the runner stops counting sim time while paused), so this waits on the wall
## clock, a physics frame at a time.
static func pause_for(t: TestContext, wall_s: float) -> void:
	var tree := t.world.get_tree()
	tree.paused = true
	var since := Time.get_ticks_msec()
	while Time.get_ticks_msec() - since < int(wall_s * 1000.0):
		OS.delay_msec(16)
		await t.frames(1)
	tree.paused = false


# --- UI (LD11, LD12) ------------------------------------------------------------------------------


## A new command menu (by path), added under the test world; null when the script does not exist
## yet.
static func command_menu(t: TestContext) -> Node:
	if not ResourceLoader.exists(COMMAND_MENU_SCRIPT):
		return null
	var menu: Node = (load(COMMAND_MENU_SCRIPT) as GDScript).new()
	menu.name = "CommandMenu"
	t.world.add_child(menu)
	return menu


## The items the menu offers now (`items()`: `[{ label, disabled, ... }]`), or [].
static func items(menu: Node) -> Array:
	return menu.items() if menu != null and menu.has_method("items") else []


## The offered item whose label contains `text` (case-insensitive), or {}.
static func item(menu: Node, text: String) -> Dictionary:
	for i in items(menu):
		if String(i.get("label", "")).to_lower().contains(text.to_lower()):
			return i
	return {}


## The labels of the offered items.
static func labels(menu: Node) -> Array:
	return items(menu).map(func(i): return String(i.get("label", "")))


## Choose the menu's item whose label contains `text` the way a click does: press the button that
## shows it (a `BaseButton` whose text it is), or the entry of a `PopupMenu` that shows it. False
## when no control shows it.
static func choose(menu: Node, text: String) -> bool:
	if menu == null:
		return false
	var wanted := text.to_lower()
	for node in menu.find_children("*", "BaseButton", true, false):
		var shown := String(node.get("text")).to_lower() if node.get("text") != null else ""
		if shown.contains(wanted) and not bool(node.get("disabled")):
			if node is CheckBox or node is CheckButton:
				node.button_pressed = not node.button_pressed
			node.pressed.emit()
			return true
	for popup: PopupMenu in menu.find_children("*", "PopupMenu", true, false):
		for i in popup.item_count:
			if popup.get_item_text(i).to_lower().contains(wanted) and not popup.is_item_disabled(i):
				popup.id_pressed.emit(popup.get_item_id(i))
				popup.index_pressed.emit(i)
				return true
	return false


## Tick (or untick) the teammate named `name` in the menu's list: the `CheckBox` whose text is that
## name.
static func tick(menu: Node, name: String, on: bool) -> bool:
	if menu == null:
		return false
	for box: BaseButton in menu.find_children("*", "BaseButton", true, false):
		if (box is CheckBox or box is CheckButton) and String(box.text) == name:
			if box.button_pressed != on:
				box.button_pressed = on
				box.toggled.emit(on)
			return true
	return false


## Give the run the screen a player has: the project's window size (1152x648), put back as the
## world goes. Headless the root viewport is 64 px square, so the camera frames the world into a
## view no window has, and a click aimed in it lands off screen: the root is resized to it. A real
## window keeps its own size (the play window opens maximized, so the bodies a test clicks sit clear
## of the result banner at its top-left), unless `exact`: a premise built on the project's size (a
## panel that cannot fit beside the click) then sees that size stretched over the window. With this
## a headless run and a windowed one see the world, and the menu over it, alike.
static func player_screen(t: TestContext, exact := false) -> void:
	var root := t.world.get_tree().root
	var want := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height")),
	)
	if DisplayServer.get_name() == "headless":
		var was := root.size
		root.size = want
		t.world.tree_exiting.connect(func() -> void: root.size = was)
		return
	if not exact:
		return
	var mode := root.content_scale_mode
	var aspect := root.content_scale_aspect
	var size := root.content_scale_size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = want
	t.world.tree_exiting.connect(
		func() -> void:
			root.content_scale_mode = mode
			root.content_scale_aspect = aspect
			root.content_scale_size = size
	)


## Wait until the view holds still (its canvas origin unmoved for five drawn frames, within 5 s):
## the premise of a click aimed at a world point. The test camera eases in from where the previous
## test left it (and on while paused), and an injected click is handled a frame after it is aimed,
## so a moving view puts it somewhere else. The camera moves once a drawn frame, and a window's
## first frames run several physics frames each, so only a drawn frame counts: else the view looks
## still before the camera has moved at all.
static func view_still(t: TestContext) -> bool:
	# The origin at the last drawn frame, that frame's number, and the drawn frames it held still.
	var last: Array = [Vector2.INF, -1, 0]
	return await t.until(func():
		var frame := Engine.get_process_frames()
		if frame == last[1]:
			return false
		var origin := t.world.get_viewport().get_canvas_transform().origin
		last[2] = last[2] + 1 if origin.distance_to(last[0]) < 0.5 else 0
		last[0] = origin
		last[1] = frame
		return last[2] >= 5, 5.0)


## The command menu's panel on screen (its `Panel` child, a Control under the menu's CanvasLayer),
## or an empty rect when it has none.
static func panel_rect(menu: Node) -> Rect2:
	var panel := menu.get_node_or_null("Panel") as Control
	return panel.get_global_rect() if panel != null else Rect2()


## LD11's dock: the menu's panel docks on the side of the screen away from the click that opened it
## (on the left, or on the right when the click is in the left half), so it never covers what it is
## about. On a player's screen, a command menu set up as Main sets it up for the human leader `lead`
## and its teammates `mates` is opened by a right-click at world point `at` (a doorway or a body),
## then each of `mates` is selected by a left-click on its body. The premise: the click and every
## selected body lie on screen, in `half` (`"left"` or `"right"`). Checks that the clicks selected
## them, that the panel docks in the other half, and that its rect holds neither the click point nor
## a selected body. The menu is closed (the tree unpaused) at the end.
static func check_dock(t: TestContext, at: Vector2, lead: Node, mates: Array, half: String) -> void:
	player_screen(t)
	var menu: Node = await open_selected(t, at, lead, mates, half, {})
	if menu == null:
		return
	var screen := t.world.get_viewport().get_visible_rect()
	var mid := screen.get_center().x
	var rect := panel_rect(menu)
	var other := "right" if half == "left" else "left"
	t.check(
		rect.has_area()
			and (rect.get_center().x >= mid if other == "right" else rect.get_center().x < mid),
		"a click in the %s half docks the panel on the %s (panel %s)" % [half, other, str(rect)],
	)
	check_uncovered(t, rect, at, mates)
	menu.close()


## LD11 with Debug on: the overlay toggle bar is built (a real `OverlayToggles`, set up as Main sets
## it up) and the command menu is set up with `right_clear`, the bar's column
## (`OverlayToggles.RESERVED_WIDTH`), as Main hands it then. A right-click at world point `at` in
## the left half opens it and each of `mates` is selected (premise: the click and the bodies on
## screen, in the left half). The panel docks on the right with its right edge `right_clear` +
## `PANEL_EDGE` from the screen's right edge, and its rect meets neither the bar's panel (read off
## the bar itself) nor the click point. By `layout`:
## - `"beside"`: the click and the bodies leave room for the panel beside them (premise: all of them
##   left of its least column), selected by a left-click each; it lies right of them all and covers
##   no selected body;
## - `"vertical"`: that column holds one of them (premise), selected by a left-click each, and they
##   all lie in the band a dock at the top or the bottom of the screen leaves free; it docks above
##   or below them all, covering no selected body;
## - `"crowded"`: a selected body lies where a panel docked on the right covers it whether it hangs
##   from the top or stands on the bottom (premise, from the panel's own height), the teammates
##   selected by ticking their boxes (the panel covers that body); the panel docks on the vertical
##   side away from the centre of the click and the bodies, the click and the bar still clear.
## The menu is closed (the tree unpaused) at the end.
static func check_clear_of_bar(
	t: TestContext,
	at: Vector2,
	lead: Node,
	mates: Array,
	layout: String,
) -> void:
	player_screen(t, layout != "beside")
	if not t.require(
			ResourceLoader.exists(OVERLAY_TOGGLES_SCRIPT),
			"the overlay toggle bar exists (%s)" % OVERLAY_TOGGLES_SCRIPT,
	):
		return
	var bar_script := load(OVERLAY_TOGGLES_SCRIPT) as GDScript
	var bar: Node = bar_script.new()
	bar.name = "OverlayToggles"
	t.world.add_child(bar)
	bar.setup({})
	var right_clear := float(bar_script.get_script_constant_map().get("RESERVED_WIDTH", 0.0))
	var bar_panel: Control = null
	for child in bar.get_children():
		if child is PanelContainer:
			bar_panel = child
	if not t.require(
			right_clear > 0.0 and bar_panel != null,
			"the bar reserves a column (RESERVED_WIDTH %s) and shows a panel" % right_clear,
	):
		return
	var menu: Node = await open_selected(
		t,
		at,
		lead,
		mates,
		"left",
		{ "right_clear": right_clear },
		layout != "crowded",
	)
	if menu == null:
		return
	var screen := t.world.get_viewport().get_visible_rect()
	var bar_rect := bar_panel.get_global_rect()
	var right_edge := screen.end.x - right_clear - PANEL_EDGE
	var column := right_edge - PANEL_WIDTH
	var at_screen := screen_of(t, at)
	var points: Array = [at_screen] + mates.map(
		func(m: Node) -> Vector2: return screen_of(t, m.global_position),
	)
	var right_of: float = points.reduce(
		func(x: float, p: Vector2) -> float: return maxf(x, p.x),
		-INF,
	)
	var rect := panel_rect(menu)
	t.check(rect.has_area(), "the panel shows (panel %s)" % str(rect))
	t.expect_near(
		rect.end.x,
		right_edge,
		1.0,
		"docked right, the panel's right edge sits right_clear + %s from the screen's right edge"
			% PANEL_EDGE,
	)
	t.check(
		not rect.intersects(bar_rect),
		"the panel %s keeps clear of the overlay bar %s" % [str(rect), str(bar_rect)],
	)
	t.check(
		not rect.has_point(at_screen),
		"the panel does not cover the click %s (panel %s)" % [str(at_screen), str(rect)],
	)
	match layout:
		"beside":
			t.check(
				right_of < column,
				"the premise: the panel's least column from x %s lies right of %s"
					% [column, str(points)],
			)
			t.check(
				rect.position.x > right_of,
				"the panel %s docks beside the click and the bodies %s" % [str(rect), str(points)],
			)
			check_uncovered(t, rect, at, mates)
		"vertical":
			t.check(
				right_of > column,
				"the premise: the panel's least column from x %s holds the click or a body of %s"
					% [column, str(points)],
			)
			var top: float = points.reduce(
				func(y: float, p: Vector2) -> float: return minf(y, p.y),
				INF,
			)
			var bottom: float = points.reduce(
				func(y: float, p: Vector2) -> float: return maxf(y, p.y),
				-INF,
			)
			t.check(
				rect.end.y < top or rect.position.y > bottom,
				"the panel %s docks above or below the click and the bodies %s"
					% [str(rect), str(points)],
			)
			check_uncovered(t, rect, at, mates)
		"crowded":
			var height := rect.size.y
			var caught := points.filter(func(p: Vector2) -> bool: return (
				p.x > right_edge - rect.size.x
				and p.y > screen.end.y - PANEL_EDGE - height
				and p.y < screen.position.y + PANEL_EDGE + height
			))
			t.check(
				not caught.is_empty(),
				"the premise: a panel %s tall docked on the right covers one of %s whether at the "
					% [height, str(points)] + "top or at the bottom",
			)
			var centre: Vector2 = points.reduce(
				func(sum: Vector2, p: Vector2) -> Vector2: return sum + p,
				Vector2.ZERO,
			) / points.size()
			var at_top := centre.y >= screen.get_center().y
			t.expect_near(
				rect.position.y if at_top else rect.end.y,
				(screen.position.y + PANEL_EDGE) if at_top else (screen.end.y - PANEL_EDGE),
				1.0,
				"the click and the bodies centred at %s, the panel %s docks at the %s of the screen"
					% [str(centre), str(rect), "top" if at_top else "bottom"],
			)
	menu.close()


## On a player's screen (call `player_screen` first), a command menu set up as Main sets it up for
## the human leader `lead` and its teammates `mates` (plus `extra` setup keys) is opened by a
## right-click at world point `at`, then each of `mates` is selected by a left-click on its body
## (`by_click`) or by ticking its box in the panel.
## The premise: the click and every selected body lie on screen, in `half` (`"left"` or `"right"`).
## Checks that the clicks selected them; the open menu, or null when a premise failed.
static func open_selected(
	t: TestContext,
	at: Vector2,
	lead: Node,
	mates: Array,
	half: String,
	extra: Dictionary,
	by_click := true,
) -> Node:
	var menu := command_menu(t)
	if not t.require(
			menu != null and menu.has_method("setup") and menu.has_signal("selection_changed"),
			"the command menu exists, with setup and selection_changed (%s)" % COMMAND_MENU_SCRIPT,
	):
		return null
	var members: Array = [lead] + mates
	var side_squad := squad(t, lead.faction, members, lead)
	if not t.require(
			side_squad != null and side_squad.has_method("resolve"),
			"the squad resolves a click",
	):
		return null
	var squad_view := {
		"leader": lead,
		"members": members.map(func(n): return { "node": n, "order": {}, "step": "" }),
	}
	menu.setup({
		"rooms": t.rooms, "teammates": mates, "view": func(): return squad_view,
		"resolve": side_squad.resolve, "leader": lead,
	}.merged(extra))
	var selected: Array = []
	menu.selection_changed.connect(func(nodes: Array) -> void: selected.assign(nodes))
	if not t.require(await view_still(t), "the view holds still before the clicks"):
		return null
	var screen := t.world.get_viewport().get_visible_rect()
	var mid := screen.get_center().x
	var points: Array = [screen_of(t, at)] + mates.map(
		func(m): return screen_of(t, m.global_position),
	)
	if not t.require(
			points.all(func(p: Vector2) -> bool: return (
				screen.has_point(p) and (p.x < mid if half == "left" else p.x >= mid)
			)),
			"the premise: the click and the bodies to select are on screen, %s half (%s of %s)"
				% [half, str(points), str(screen)],
	):
		return null
	click(t, at, MOUSE_BUTTON_RIGHT)
	await t.frames(2)
	if not t.require(menu.is_open(), "the right-click opens the menu"):
		return null
	for m: Node in mates:
		if by_click:
			click(t, m.global_position, MOUSE_BUTTON_LEFT)
		else:
			tick(menu, String(m.name), true)
		await t.frames(2)
	t.check(
		mates.all(func(m: Node) -> bool: return selected.has(m)),
		"%s selects it (selected %s)" % [
			"a left-click on each teammate's body" if by_click else "ticking each teammate",
			str(selected.map(func(n: Node) -> String: return String(n.name))),
		],
	)
	return menu


## Checks that the command menu's panel `rect` holds neither the click at world point `at` nor the
## body of any of the selected `mates`.
static func check_uncovered(t: TestContext, rect: Rect2, at: Vector2, mates: Array) -> void:
	var at_screen := screen_of(t, at)
	t.check(
		not rect.has_point(at_screen),
		"the panel does not cover the click %s (panel %s)" % [str(at_screen), str(rect)],
	)
	for m: Node in mates:
		var p := screen_of(t, m.global_position)
		t.check(
			not rect.has_point(p),
			"the panel does not cover the selected %s at %s (panel %s)" % [
				m.name,
				str(p),
				str(rect),
			],
		)


## Where world point `p` is on the screen of the test world's viewport (what a click there sends).
static func screen_of(t: TestContext, p: Vector2) -> Vector2:
	return t.world.get_viewport().get_canvas_transform() * p


## Click mouse button `button` at world point `p` (a motion there first, so the pointer is where the
## click is), as the test's own input.
static func click(t: TestContext, p: Vector2, button: MouseButton) -> void:
	# An injected event is in the window's pixels: a stretched root (`player_screen`) maps it.
	var at := t.world.get_viewport().get_final_transform() * screen_of(t, p)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	TestContext.inject(motion)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		TestContext.inject(ev)


# --- Stack orders at the Terrace house's back door (LD9) ------------------------------------------


## Which side of the back door point `p` lies on along its wall: `north`, `south`, or `door` (within
## the opening's width).
static func back_side(p: Vector2) -> String:
	if p.y < BACK_Y - BACK_HALF:
		return "north"
	if p.y > BACK_Y + BACK_HALF:
		return "south"
	return "door"


## Where actor `id`'s running entry has it stand in the stack (`debug_entry()["stack_point"]`), or
## INF.
static func stack_point(t: TestContext, id: StringName) -> Vector2:
	var e: Dictionary = brain(t, id).debug_entry()
	var p = e.get("stack_point", Vector2.INF)
	return p if p is Vector2 else Vector2.INF


## Order a stack at the back door through `squad.issue` the way the command menu asks for it (LD16):
## `{ kind: "stack", to, pos, bang, mode, wait_go }`, `bang` being mode != quiet (part 1's key). The
## order posted, or {}.
static func stack_order(
	s: Node,
	to: Array,
	pos: Vector2,
	mode: String,
	wait_go: bool,
) -> Dictionary:
	return issue(
		s,
		{
			"kind": STACK,
			"to": to,
			"pos": pos,
			"bang": mode != "quiet",
			"mode": mode,
			"wait_go": wait_go,
		},
	)


## The leader's Go for the held stack at the doorway nearest `pos` (LD13):
## `squad.issue({ kind: "go", pos })`. The order posted, or {}.
static func go(s: Node, pos: Vector2) -> Dictionary:
	return issue(s, { "kind": GO, "pos": pos })


## Whether every actor of `ids` has radioed entry step `step` about doorway `opening`.
static func all_called(t: TestContext, ids: Array, step: String, opening: String) -> bool:
	return ids.all(func(id): return Entry.first_call_time(t, step, id, opening) < INF)


## The actors of `ids` sorted by the stack slot they last claimed at doorway `opening` (from their
## radio); those with no claim last.
static func by_slot(t: TestContext, ids: Array, opening: String) -> Array:
	var slot_of := {}
	for id in ids:
		var claims := Entry.calls(t, "", id).filter(
			func(c): return String(c.get("opening", "")) == opening,
		)
		slot_of[id] = int(claims.back().get("slot", 99)) if not claims.is_empty() else 99
	var out := ids.duplicate()
	out.sort_custom(func(a, b): return slot_of[a] < slot_of[b])
	return out


## Whether actor `id` is in its stack slot (its entry's phase is past the approach: `stack` or
## later).
static func stacked(t: TestContext, id: StringName) -> bool:
	var phase := String(brain(t, id).debug_entry().get("phase", ""))
	return phase != "" and phase != "approach"
