extends CanvasLayer
## UI domain: the command menu (`docs/leadership.md` LD11), how the human leader orders its
## teammates. Main builds it only when the human leads its side ("Lead the team" in the setup
## window). A right-click (`Keybinds.COMMAND`) pauses the whole tree and opens the menu on what is
## under the cursor:
## - a teammate within `PICK_RADIUS`: "Select <name>" / "Deselect <name>" (the menu stays open), and
##   "Go into the <room>" while it holds a held stack that has had no go (LD13: the stack's point
##   stands right by its doorway);
## - else a doorway the squad resolves a stack at the click to (its `resolve` callable: the doorway
##   nearest the click within its width): "Stack into the <room> (quiet)", "Stack into the <room>
##   with stun" and "Stack into the <room> with frag", `<room>` the room that stack goes into (the
##   squad's `into`, named from the plain room dicts it was set up with), so the label names the
##   room of the order; the stun item is greyed while no recipient carries a stun
##   (`Character.item_count(ItemRegistry.STUN_SLOT)`, D1), the frag item while none carries a frag
##   (`FRAG_SLOT`, D15); the panel's "Hold for my go" checkbox (off at first, kept while the match
##   runs, D19) makes the stack chosen wait for the leader's go (LD13); "Go into the <room>" while a
##   member of the squad's view holds a held stack there that has had no go, whoever is selected
##   (D13); and "Ambush the doorway from the <room>", `<room>` the one on the click's side of its
##   wall, as the squad resolves the ambush (LD15, D17);
## - else a room: "Defend the <room>";
## - and "Cancel order" while a recipient holds an order (the squad's `view()`).
## The panel also lists the teammates to tick. The recipients are the selection (ticked, or picked
## by a left-click on a teammate's body while the menu is open), or every living teammate when
## nothing is selected; never the human. The selection lasts until it is changed, and a dead
## teammate leaves it. Choosing an order emits `order_requested` and closes the menu; Escape closes
## it too (consumed in `_input`, so Main's MENU never sees it); closing unpauses the tree. Space
## stays the player's INTERACT.
##
## The panel docks on the side of the screen away from the click it is open on: on the left, or on
## the right when the click lies in the left half, so it never covers the teammate or doorway it is
## about; a ring marks the clicked point. A decoupled observer: it reads its teammates through
## the Character API only (`global_position`, `name`, `is_dead`, `item_count`) and the squad through
## its `view()` and `resolve()` callables, emits plain requests and works out no AI id: the squad
## (interface 21) resolves the click into its doorway, side and room. `PROCESS_MODE_ALWAYS`, so it
## works while the tree is paused.

## Emitted when an order is chosen: `{ kind: "stack", to, pos, bang, mode, wait_go }` (`pos` the
## click itself, `mode` quiet / stun / frag, `bang` mode != quiet as part 1 had it, `wait_go` the
## "Hold for my go" box), `{ kind: "go", pos }` (the held stack at that doorway goes, LD13),
## `{ kind: "ambush", to, pos }` (LD15), `{ kind: "defend_room", to, room }` (a room key) or
## `{ kind: "cancel", to }` (the recipients holding an order). `to` is the recipients (characters).
## Main hands it to the squad's `issue`.
signal order_requested(request: Dictionary)
## Emitted when the highlighted selection changes: the selected teammates while the menu is open, []
## once it closes (the order markers' `set_selection`).
signal selection_changed(nodes: Array)

## World-space radius (px) around the cursor within which a click picks a teammate's body.
const PICK_RADIUS := 28.0
## The panel's place on screen: its gap to the screen's edge it docks against, its top (below the
## match HUD's timer) and its least width.
const PANEL_EDGE := 24.0
const PANEL_TOP := 120.0
const PANEL_WIDTH := 440.0
const TITLE_FONT := 28
const ITEM_FONT := 26
const LIST_FONT := 22
const HINT_FONT := 18
## The ring on the clicked point: its radius (screen px) and colour.
const MARK_RADIUS := 14.0
const MARK_COLOR := Color(1.0, 0.85, 0.3, 0.95)

## The house's rooms (`WorldGen.get_rooms`: `{ key, type, rect }`).
var _rooms: Array = []
## The characters the human may order (its squad without itself), in squad order.
var _teammates: Array = []
## The squad's `view()`: `{ leader, members: [{ node, order, step }] }`.
var _view: Callable
## The squad's `resolve(request)`: what a stack at a click names (`{ opening, pos, into, ... }`, or
## {}).
var _resolve: Callable
## The human: the menu opens only while the view names it the leader (null: no such check).
var _leader: Node = null
## The selected teammates.
var _selection: Array = []
## Whether the menu is open.
var _open := false
## Whether opening the menu paused the tree (closing then unpauses it).
var _paused_tree := false
## The world point the menu is open on.
var _click := Vector2.ZERO
## What is offered now: `{ label, disabled, act: Callable, why }`.
var _items: Array = []
## "Hold for my go" is ticked: a stack chosen waits for the leader's go (LD13; kept across opens,
## D19).
var _hold_go := false
## The panel, docked away from the click (`_dock`), holding everything below.
var _panel: PanelContainer
## Names what the menu is open on.
var _title: Label
## "Orders go to: ...".
var _recipients: Label
## The offered items' buttons.
var _item_box: VBoxContainer
## The teammates' CheckBoxes.
var _list_box: VBoxContainer
## Teammate instance id -> its CheckBox in the list.
var _checks := {}
## "Hold for my go".
var _hold_box: CheckBox
## Full-screen, mouse-ignoring: draws the ring on the clicked point.
var _mark: Control


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40


func _exit_tree() -> void:
	if _open and _paused_tree:
		# A menu freed while open (the match torn down) never leaves the game paused.
		get_tree().paused = false


## Escape closes the open menu; consumed here, before Main's `_unhandled_input` would read it as
## MENU.
func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed(Keybinds.MENU) and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


## COMMAND (a right-click by default) opens the menu on the point under the cursor; while it is
## open, a left-click on a teammate's body toggles it in the selection. Clicks on the panel never
## get here (it takes them first).
func _unhandled_input(event: InputEvent) -> void:
	var screen: Vector2 = (event.position
			if event is InputEventMouse
			else get_viewport().get_mouse_position())
	if event.is_action_pressed(Keybinds.COMMAND) and not event.is_echo():
		if _may_open():
			open_at(_world_of(screen))
			get_viewport().set_input_as_handled()
	elif (_open
			and event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		var mate := _teammate_at(_world_of(screen))
		if mate != null:
			_toggle(mate, not _selection.has(mate))
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open:
		# The camera may still zoom while paused: keep the ring on the clicked point.
		_mark.queue_redraw()


## Set the menu up: `{ rooms, teammates, view, resolve, leader? }`, `rooms` the house's (plain
## dicts), `teammates` the characters it may order, `view` and `resolve` the squad's `view()` and
## `resolve(request)` callables (with no `resolve` no doorway is offered) and `leader` the human
## (the menu then opens only while it leads). Called by Main once the squads are built.
func setup(config: Dictionary) -> void:
	_rooms = config.get("rooms", [])
	_teammates = (config.get("teammates", []) as Array).filter(func(n): return n is Node)
	var view = config.get("view")
	_view = view if view is Callable else Callable()
	var resolve = config.get("resolve")
	_resolve = resolve if resolve is Callable else Callable()
	_leader = config.get("leader") as Node
	_build()


## Pause the tree and open the menu on world point `at`: the items for what lies there.
func open_at(at: Vector2) -> void:
	if not _may_open():
		return
	_click = at
	if not _open:
		_open = true
		_paused_tree = not get_tree().paused
		get_tree().paused = true
		_panel.visible = true
	_dock()
	_drop_dead()
	_refresh()
	selection_changed.emit(_selection.duplicate())


## Close the menu (no order) and unpause the tree if opening it paused it.
func close() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	_set_items([])
	_mark.queue_redraw()
	if _paused_tree and is_inside_tree():
		get_tree().paused = false
	_paused_tree = false
	selection_changed.emit([])


## Whether the menu is open.
func is_open() -> bool:
	return _open


## What the menu offers now, `[{ label, disabled }]` in display order; [] while it is closed.
func items() -> Array:
	return _items.map(func(i): return { "label": i["label"], "disabled": i["disabled"] })


# --- What lies under the click --------------------------------------------------------------------


## Rebuild the panel for the point the menu is open on: its title, the recipients line and the
## items.
func _refresh() -> void:
	var offered: Array = []
	var mate := _teammate_at(_click)
	var door := {} if mate != null else _stack_at(_click)
	if mate != null:
		_title.text = String(mate.name)
		var picked := _selection.has(mate)
		offered.append(_item(
			"%s %s" % ["Deselect" if picked else "Select", mate.name],
			false,
			_toggle.bind(mate, not picked),
		))
		var held := _held_order_of(mate)
		if not held.is_empty():
			offered.append(_item(
				"Go into the %s" % _room_name(_room_by_key(String(held.get("into", "")))),
				false,
				_go.bind(held["pos"]),
			))
	elif not door.is_empty():
		var into := _room_name(_room_by_key(String(door.get("into", ""))))
		_title.text = "Doorway into the %s" % into
		if _held_at(String(door.get("opening", ""))):
			offered.append(_item("Go into the %s" % into, false, _go.bind(_click)))
		offered.append(_item("Stack into the %s (quiet)" % into, false, _stack.bind("quiet")))
		offered.append(_item(
			"Stack into the %s with stun" % into, not _recipients_carry(ItemRegistry.STUN_SLOT),
			_stack.bind("stun"), "Nobody it would go to carries a stun grenade.",
		))
		offered.append(_item(
			"Stack into the %s with frag" % into, not _recipients_carry(ItemRegistry.FRAG_SLOT),
			_stack.bind("frag"), "Nobody it would go to carries a frag grenade.",
		))
		var from := _ambush_from(_click)
		if from != "":
			offered.append(_item(
				"Ambush the doorway from the %s" % _room_name(_room_by_key(from)), false,
				_order.bind({ "kind": "ambush", "pos": _click }),
			))
	else:
		var room := _room_at(_click)
		_title.text = "The %s" % _room_name(room) if not room.is_empty() else "Outside"
		if not room.is_empty():
			offered.append(_item(
				"Defend the %s" % _room_name(room),
				false,
				_order.bind({ "kind": "defend_room", "room": String(room["key"]) }),
			))
	if not _ordered_recipients().is_empty():
		offered.append(_item("Cancel order", false, _cancel))
	_recipients.text = ("Orders go to: %s"
			% (", ".join(_selection.map(func(n): return String(n.name)))
					if not _selection.is_empty()
					else "the whole squad"))
	_set_items(offered)
	_mark.queue_redraw()


## The living teammate nearest world point `at` within `PICK_RADIUS`, or null.
func _teammate_at(at: Vector2) -> Node:
	var best: Node = null
	var best_d := PICK_RADIUS
	for mate in _teammates:
		if not _alive(mate):
			continue
		var d: float = (mate.global_position as Vector2).distance_to(at)
		if d <= best_d:
			best_d = d
			best = mate
	return best


## What a stack ordered at world point `at` names, as the squad resolves it
## (`{ opening, pos, into, ... }`), or {} for no doorway there.
func _stack_at(at: Vector2) -> Dictionary:
	var out = _resolve.call({ "kind": "stack", "pos": at }) if _resolve.is_valid() else {}
	return out if out is Dictionary else {}


## The room an ambush ordered at world point `at` is laid from (the squad's `resolve`: the click's
## side of the doorway's wall), or "".
func _ambush_from(at: Vector2) -> String:
	var out = _resolve.call({ "kind": "ambush", "pos": at }) if _resolve.is_valid() else {}
	return String((out as Dictionary).get("room", "")) if out is Dictionary else ""


## Whether a member of the squad's view holds a stack order at doorway `opening` that waits for the
## leader's go and has not had it (its row's `held`, LD13).
func _held_at(opening: String) -> bool:
	var view: Dictionary = _view.call() if _view.is_valid() else {}
	for row: Dictionary in view.get("members", []):
		if bool(row.get("held", false)) and String(row["order"].get("opening", "")) == opening:
			return true
	return false


## The held stack order `mate` holds in the squad's view (its row's `held`) with its doorway's
## centre (`pos`), or {}.
func _held_order_of(mate: Node) -> Dictionary:
	var view: Dictionary = _view.call() if _view.is_valid() else {}
	for row: Dictionary in view.get("members", []):
		if (row.get("node") == mate
				and bool(row.get("held", false))
				and row["order"].get("pos") is Vector2):
			return row["order"]
	return {}


## The room whose rect holds world point `at`, or {}.
func _room_at(at: Vector2) -> Dictionary:
	for r: Dictionary in _rooms:
		if (r["rect"] as Rect2).has_point(at):
			return r
	return {}


## Room `key`'s dict, or {}.
func _room_by_key(key: String) -> Dictionary:
	for r: Dictionary in _rooms:
		if String(r["key"]) == key:
			return r
	return {}


## A room as the menu names it: its type, words apart ("living_room" -> "living room").
func _room_name(room: Dictionary) -> String:
	return (String(room.get("type", room.get("key", "room"))).replace("_", " ")
			if not room.is_empty()
			else "room")


# --- Recipients and orders ------------------------------------------------------------------------


## Who an order goes to: the selection, or every living teammate when nothing is selected.
func _recipients_now() -> Array:
	return _selection.duplicate() if not _selection.is_empty() else _teammates.filter(_alive)


## Whether any recipient carries a grenade of inventory slot `slot` (D1, D15: a stun or frag stack
## is offered only then).
func _recipients_carry(slot: int) -> bool:
	return _recipients_now().any(
		func(n): return n.has_method("item_count") and int(n.item_count(slot)) > 0,
	)


## The recipients that hold an order now (the squad's `view()`).
func _ordered_recipients() -> Array:
	var held: Array = []
	var view: Dictionary = _view.call() if _view.is_valid() else {}
	for row: Dictionary in view.get("members", []):
		if not (row.get("order", {}) as Dictionary).is_empty():
			held.append(row.get("node"))
	return _recipients_now().filter(func(n): return held.has(n))


## Emit `request` for the recipients now and close the menu.
func _order(request: Dictionary) -> void:
	var out := request.duplicate()
	out["to"] = _recipients_now()
	close()
	order_requested.emit(out)


## Order a stack at the click in `mode` (quiet / stun / frag), held for the leader's go while "Hold
## for my go" is ticked.
func _stack(mode: String) -> void:
	_order({
		"kind": "stack",
		"pos": _click,
		"bang": mode != "quiet",
		"mode": mode,
		"wait_go": _hold_go,
	})


## The leader's go for the held stack at the doorway at `at` (the squad sends it to whoever holds it
## there) and close the menu.
func _go(at: Vector2) -> void:
	var request := { "kind": "go", "pos": at }
	close()
	order_requested.emit(request)


## Cancel the recipients' orders and close the menu.
func _cancel() -> void:
	var to := _ordered_recipients()
	close()
	order_requested.emit({ "kind": "cancel", "to": to })


## Put `mate` in the selection (`on`) or take it out, tick its box to match, and redraw an open
## menu.
func _toggle(mate: Node, on: bool) -> void:
	if on and _alive(mate) and not _selection.has(mate):
		_selection.append(mate)
	elif not on:
		_selection.erase(mate)
	var box: CheckBox = _checks.get(mate.get_instance_id())
	if box != null and box.button_pressed != _selection.has(mate):
		box.set_pressed_no_signal(_selection.has(mate))
	if _open:
		_refresh()
		selection_changed.emit(_selection.duplicate())


## A dead teammate leaves the selection and its box is disabled.
func _drop_dead() -> void:
	for mate in _teammates:
		var box: CheckBox = _checks.get(mate.get_instance_id()) if is_instance_valid(mate) else null
		if not _alive(mate):
			_selection.erase(mate)
			if box != null:
				box.set_pressed_no_signal(false)
				box.disabled = true


## Whether `n` is a living character.
func _alive(n) -> bool:
	return n is Node and is_instance_valid(n) and n.get("is_dead") != true


## Whether the menu may open: it was set up and, when it was given the human, the squad's view still
## names the human its leader.
func _may_open() -> bool:
	if _panel == null:
		return false
	if _leader == null:
		return true
	var view: Dictionary = _view.call() if _view.is_valid() else {}
	return is_instance_valid(_leader) and view.get("leader") == _leader


## Dock the panel on the side of the screen away from the click it is open on (LD11): on the left,
## or on the right when the click lies in the left half. Anchored to that edge, it grows away from
## it as wide as its items need.
func _dock() -> void:
	var screen := get_viewport().get_visible_rect()
	var right := (get_viewport().get_canvas_transform() * _click).x < screen.get_center().x
	var edge := 1.0 if right else 0.0
	var gap := -PANEL_EDGE if right else PANEL_EDGE
	# Pushing the opposite anchor along: a left anchor moved past the right one would be held back.
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		_panel.set_anchor_and_offset(side, edge, gap, true)
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		_panel.set_anchor_and_offset(side, 0.0, PANEL_TOP, true)
	_panel.grow_horizontal = (
		Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	)


## World point under screen point `screen` (the world's canvas transform).
func _world_of(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


# --- The panel ------------------------------------------------------------------------------------


## One offered item: its label, whether it is greyed out, what choosing it does, and why it is
## greyed (its tooltip then).
func _item(label: String, disabled: bool, act: Callable, why := "") -> Dictionary:
	return { "label": label, "disabled": disabled, "act": act, "why": why }


## Show `offered` as the panel's buttons, replacing the ones shown.
func _set_items(offered: Array) -> void:
	_items = offered
	for old in _item_box.get_children():
		_item_box.remove_child(old)
		old.queue_free()
	for i: Dictionary in offered:
		var button := Button.new()
		button.text = i["label"]
		button.disabled = i["disabled"]
		button.focus_mode = Control.FOCUS_NONE  # Space must never press it (it stays INTERACT)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", ITEM_FONT)
		if i["disabled"]:
			button.tooltip_text = i["why"]
		button.pressed.connect(i["act"])
		_item_box.add_child(button)


## Build the hidden panel (title, recipients, items, "Hold for my go", the teammate list, the hint)
## and the ring layer.
func _build() -> void:
	if _panel != null:
		return
	_mark = Control.new()
	_mark.name = "ClickMark"
	_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.draw.connect(_draw_mark)
	add_child(_mark)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # a click on the panel never reaches the world
	_panel.visible = false
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_title = _label(box, TITLE_FONT)
	_recipients = _label(box, LIST_FONT)
	_recipients.modulate = Color(1, 1, 1, 0.75)
	_item_box = VBoxContainer.new()
	_item_box.add_theme_constant_override("separation", 4)
	box.add_child(_item_box)
	_hold_box = CheckBox.new()
	_hold_box.text = "Hold for my go"
	_hold_box.focus_mode = Control.FOCUS_NONE
	_hold_box.add_theme_font_size_override("font_size", LIST_FONT)
	_hold_box.toggled.connect(func(on: bool): _hold_go = on)
	box.add_child(_hold_box)
	box.add_child(HSeparator.new())
	var heading := _label(box, LIST_FONT)
	heading.text = "Teammates"
	_list_box = VBoxContainer.new()
	box.add_child(_list_box)
	for mate: Node in _teammates:
		var check := CheckBox.new()
		check.text = String(mate.name)
		check.focus_mode = Control.FOCUS_NONE
		check.add_theme_font_size_override("font_size", LIST_FONT)
		check.toggled.connect(func(on: bool): _toggle(mate, on))
		_list_box.add_child(check)
		_checks[mate.get_instance_id()] = check
	var hint := _label(box, HINT_FONT)
	hint.text = "Click a teammate to select it · Esc closes"
	hint.modulate = Color(1, 1, 1, 0.6)


## A new Label at font size `size`, added under `parent`.
func _label(parent: Control, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


## The ring on the clicked point, while the menu is open.
func _draw_mark() -> void:
	if not _open:
		return
	var at := get_viewport().get_canvas_transform() * _click
	_mark.draw_arc(at, MARK_RADIUS, 0.0, TAU, 24, MARK_COLOR, 3.0)
	_mark.draw_circle(at, 3.0, MARK_COLOR)
