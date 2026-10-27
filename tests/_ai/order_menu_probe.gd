extends RefCounted
## Shared helpers for the leadership tests (not a test itself):
## `const OrderMenu := preload("res://tests/_ai/order_menu_probe.gd")`. The human leader's command
## menu and the order markers (`docs/leadership.md` LD11, LD12), on a player's screen: a menu made
## by path (`command_menu`), its items and how a click chooses one (`items`, `item`, `labels`,
## `choose`, `tick`, `click`), the screen a player has (`player_screen`, `view_still`), and LD11's
## dock checks (`check_dock`, `check_clear_of_bar`). The menu and the markers are loaded by path and
## read duck-typed, so a missing piece fails an assertion that names it. The squad a menu is set up
## over is built by `order_probe.gd` (`Order.squad`).

const COMMAND_MENU_SCRIPT := "res://scenes/ui/hud/command_menu.gd"
const ORDER_MARKERS_SCRIPT := "res://scenes/ui/hud/order_markers.gd"
const OVERLAY_TOGGLES_SCRIPT := "res://scenes/ui/overlays/overlay_toggles.gd"
const Order := preload("res://tests/_ai/order_probe.gd")
# --- The command menu's panel on screen (LD11) ----------------------------------------------------
## Its gap to the screen edge it docks against (past the overlay bar's column when Debug is on) and
## its least width (screen px).
const PANEL_EDGE := 24.0
const PANEL_WIDTH := 440.0


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
## view no window has, and a click aimed in it lands off screen: the root is resized to it, which
## also gets the bodies a player would see drawn, not culled (what the grenade perf guards need,
## `tests/perf/grenade_*_stress_test.gd`). A real window keeps its own size (the play window opens
## maximized, so the bodies a test clicks sit clear of the result banner at its top-left), unless
## `exact`: a premise built on the project's size (a panel that cannot fit beside the click) then
## sees that size stretched over the window. With this a headless run and a windowed one see the
## world, and the menu over it, alike.
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
static func _panel_rect(menu: Node) -> Rect2:
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
	var menu: Node = await _open_selected(t, at, lead, mates, { "half": half })
	if menu == null:
		return
	var screen := t.world.get_viewport().get_visible_rect()
	var mid := screen.get_center().x
	var rect := _panel_rect(menu)
	var other := "right" if half == "left" else "left"
	t.check(
		rect.has_area()
			and (rect.get_center().x >= mid if other == "right" else rect.get_center().x < mid),
		"a click in the %s half docks the panel on the %s (panel %s)" % [half, other, str(rect)],
	)
	_check_uncovered(t, rect, at, mates)
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
	var bar := _overlay_bar(t)
	var right_clear := float(
		(bar.get_script() as GDScript).get_script_constant_map().get("RESERVED_WIDTH", 0.0),
	)
	var bar_panel: Control = null
	for child in bar.get_children():
		if child is PanelContainer:
			bar_panel = child
	if not t.require(
			right_clear > 0.0 and bar_panel != null,
			"the bar reserves a column (RESERVED_WIDTH %s) and shows a panel" % right_clear,
	):
		return
	var menu: Node = await _open_selected(t, at, lead, mates, {
		"half": "left", "setup": { "right_clear": right_clear }, "by_click": layout != "crowded",
	})
	if menu == null:
		return
	var right_edge := t.world.get_viewport().get_visible_rect().end.x - right_clear - PANEL_EDGE
	var points: Array = [_screen_of(t, at)] + mates.map(
		func(m: Node) -> Vector2: return _screen_of(t, m.global_position),
	)
	var rect := _panel_rect(menu)
	_check_docked_right(t, rect, at, right_edge, bar_panel.get_global_rect())
	match layout:
		"beside":
			_check_beside(t, rect, right_edge - PANEL_WIDTH, points)
			_check_uncovered(t, rect, at, mates)
		"vertical":
			_check_vertical(t, rect, right_edge - PANEL_WIDTH, points)
			_check_uncovered(t, rect, at, mates)
		"crowded":
			_check_crowded(t, rect, right_edge, points)
	menu.close()


## A real overlay toggle bar (`OverlayToggles`) in the world, set up as Main sets it up.
static func _overlay_bar(t: TestContext) -> Node:
	var bar: Node = (load(OVERLAY_TOGGLES_SCRIPT) as GDScript).new()
	bar.name = "OverlayToggles"
	t.world.add_child(bar)
	bar.setup({})
	return bar


## `check_clear_of_bar`'s checks of the panel `rect` docked right: it shows, its right edge is at
## `right_edge`, and it meets neither the bar's panel (`bar_rect`) nor the click at world point
## `at`.
static func _check_docked_right(
		t: TestContext, rect: Rect2, at: Vector2, right_edge: float, bar_rect: Rect2
) -> void:
	var at_screen := _screen_of(t, at)
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


## The rightmost x of `points` (screen points).
static func _right_of(points: Array) -> float:
	return points.reduce(func(x: float, p: Vector2) -> float: return maxf(x, p.x), -INF)


## `check_clear_of_bar`'s `"beside"` checks: the click and the bodies (`points`) lie left of the
## panel's least `column` (premise), and the panel `rect` lies right of them all.
static func _check_beside(t: TestContext, rect: Rect2, column: float, points: Array) -> void:
	var right_of := _right_of(points)
	t.check(
		right_of < column,
		"the premise: the panel's least column from x %s lies right of %s" % [column, str(points)],
	)
	t.check(
		rect.position.x > right_of,
		"the panel %s docks beside the click and the bodies %s" % [str(rect), str(points)],
	)


## `check_clear_of_bar`'s `"vertical"` checks: the panel's least `column` holds the click or a body
## of `points` (premise), and the panel `rect` docks above or below them all.
static func _check_vertical(t: TestContext, rect: Rect2, column: float, points: Array) -> void:
	t.check(
		_right_of(points) > column,
		"the premise: the panel's least column from x %s holds the click or a body of %s"
			% [column, str(points)],
	)
	var top: float = points.reduce(func(y: float, p: Vector2) -> float: return minf(y, p.y), INF)
	var bottom: float = points.reduce(
		func(y: float, p: Vector2) -> float: return maxf(y, p.y),
		-INF,
	)
	t.check(
		rect.end.y < top or rect.position.y > bottom,
		"the panel %s docks above or below the click and the bodies %s" % [str(rect), str(points)],
	)


## `check_clear_of_bar`'s `"crowded"` checks: a panel docked on the right (its right edge at
## `right_edge`) covers one of `points` whether at the top or the bottom (premise), and the panel
## `rect` docks on the vertical side away from their centre.
static func _check_crowded(t: TestContext, rect: Rect2, right_edge: float, points: Array) -> void:
	var screen := t.world.get_viewport().get_visible_rect()
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


## On a player's screen (call `player_screen` first), a command menu set up as Main sets it up for
## the human leader `lead` and its teammates `mates` (plus `how.setup`'s setup keys) is opened by a
## right-click at world point `at`, then each of `mates` is selected by a left-click on its body
## (`how.by_click`, true by default) or by ticking its box in the panel.
## The premise: the click and every selected body lie on screen, in `how.half` (`"left"` or
## `"right"`). Checks that the clicks selected them; the open menu, or null when a premise failed.
static func _open_selected(
	t: TestContext,
	at: Vector2,
	lead: Node,
	mates: Array,
	how: Dictionary,
) -> Node:
	var by_click: bool = how.get("by_click", true)
	var menu := command_menu(t)
	if not t.require(
			menu != null and menu.has_method("setup") and menu.has_signal("selection_changed"),
			"the command menu exists, with setup and selection_changed (%s)" % COMMAND_MENU_SCRIPT,
	):
		return null
	if not _set_up_menu(t, menu, lead, mates, how.get("setup", {})):
		return null
	var selected: Array = []
	menu.selection_changed.connect(func(nodes: Array) -> void: selected.assign(nodes))
	if not t.require(await view_still(t), "the view holds still before the clicks"):
		return null
	if not _on_screen(t, at, mates, String(how["half"])):
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


## Sets `menu` up as Main sets it up for the human leader `lead` and its teammates `mates`, plus
## `extra` setup keys; false when their squad does not resolve a click.
static func _set_up_menu(
		t: TestContext, menu: Node, lead: Node, mates: Array, extra: Dictionary
) -> bool:
	var members: Array = [lead] + mates
	var side_squad := Order.squad(t, lead.faction, members, lead)
	if not t.require(
			side_squad != null and side_squad.has_method("resolve"),
			"the squad resolves a click",
	):
		return false
	var squad_view := {
		"leader": lead,
		"members": members.map(func(n): return { "node": n, "order": {}, "step": "" }),
	}
	menu.setup({
		"rooms": t.rooms, "teammates": mates, "view": func(): return squad_view,
		"resolve": side_squad.resolve, "leader": lead,
	}.merged(extra))
	return true


## `_open_selected`'s premise: the click at world point `at` and the bodies of `mates` are on
## screen, in `half` (`"left"` or `"right"`).
static func _on_screen(t: TestContext, at: Vector2, mates: Array, half: String) -> bool:
	var screen := t.world.get_viewport().get_visible_rect()
	var mid := screen.get_center().x
	var points: Array = [_screen_of(t, at)] + mates.map(
		func(m): return _screen_of(t, m.global_position),
	)
	return t.require(
		points.all(func(p: Vector2) -> bool: return (
			screen.has_point(p) and (p.x < mid if half == "left" else p.x >= mid)
		)),
		"the premise: the click and the bodies to select are on screen, %s half (%s of %s)"
			% [half, str(points), str(screen)],
	)


## Checks that the command menu's panel `rect` holds neither the click at world point `at` nor the
## body of any of the selected `mates`.
static func _check_uncovered(t: TestContext, rect: Rect2, at: Vector2, mates: Array) -> void:
	var at_screen := _screen_of(t, at)
	t.check(
		not rect.has_point(at_screen),
		"the panel does not cover the click %s (panel %s)" % [str(at_screen), str(rect)],
	)
	for m: Node in mates:
		var p := _screen_of(t, m.global_position)
		t.check(
			not rect.has_point(p),
			"the panel does not cover the selected %s at %s (panel %s)" % [
				m.name,
				str(p),
				str(rect),
			],
		)


## Where world point `p` is on the screen of the test world's viewport (what a click there sends).
static func _screen_of(t: TestContext, p: Vector2) -> Vector2:
	return t.world.get_viewport().get_canvas_transform() * p


## Click mouse button `button` at world point `p` (a motion there first, so the pointer is where the
## click is), as the test's own input.
static func click(t: TestContext, p: Vector2, button: MouseButton) -> void:
	# An injected event is in the window's pixels: a stretched root (`player_screen`) maps it.
	var at := t.world.get_viewport().get_final_transform() * _screen_of(t, p)
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
