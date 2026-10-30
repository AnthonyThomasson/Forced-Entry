extends PanelContainer
## UI domain: the command menu's panel (`command_menu.gd`, `docs/leadership.md` LD11), the widgets
## it shows: the title naming what the menu is open on, the "Orders go to:" line, the offered items'
## buttons, the "Hold for my go" box, a box per teammate to tick and a hint. The menu builds it (as
## its child named `Panel`), fills it and tells it where to dock; it holds no reference back: the
## teammates' boxes call the toggle the menu hands `build`.
##
## It docks on the side of the screen away from the click the menu is open on: on the left, or on
## the right when the click lies in the left half. Docked on the right it keeps clear of
## `right_clear` (the overlay toggle bar's column when Debug is on), and where it would cover the
## click or a selected teammate there it docks at the top or the bottom of the screen instead, away
## from them.

## The panel's place on screen: its gap to the screen's edge it docks against (and to the top or
## bottom edge in a vertical dock), its top (below the match HUD's timer) and its least width.
const PANEL_EDGE := 24.0
const PANEL_TOP := 120.0
const PANEL_WIDTH := 440.0
## How near (screen px) the docked panel may come to the click and to a selected teammate's body.
const POINT_CLEAR := 24.0
const TITLE_FONT := 28
const ITEM_FONT := 26
const LIST_FONT := 22
const HINT_FONT := 18

## Screen width (px) from the right edge the panel keeps clear when docked on the right: the overlay
## toggle bar's column while Debug is on, else 0.
var right_clear := 0.0
## "Hold for my go" is ticked: a stack chosen waits for the leader's go (LD13; kept across opens,
## D19).
var hold_go := false
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


## Build the hidden panel (title, recipients, items, "Hold for my go", the teammate list, the hint):
## a box per teammate of `teammates`, ticking it calling `toggle(mate, on)`.
func build(teammates: Array, toggle: Callable) -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP  # a click on the panel never reaches the world
	visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
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
	_hold_box.toggled.connect(func(on: bool): hold_go = on)
	box.add_child(_hold_box)
	box.add_child(HSeparator.new())
	_build_teammates(box, teammates, toggle)
	var hint := _label(box, HINT_FONT)
	hint.text = "Click a teammate to select it · Esc closes"
	hint.modulate = Color(1, 1, 1, 0.6)


## Name what the menu is open on (`title`) and whom its orders go to (`recipients`).
func set_heading(title: String, recipients: String) -> void:
	_title.text = title
	_recipients.text = recipients


## Show `offered` (`{ label, disabled, act: Callable, why }`) as the panel's buttons, replacing the
## ones shown.
func set_items(offered: Array) -> void:
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


## Tick `mate`'s box (`on`) or untick it, without its `toggled`.
func tick(mate: Node, on: bool) -> void:
	var box: CheckBox = _checks.get(mate.get_instance_id())
	if box != null and box.button_pressed != on:
		box.set_pressed_no_signal(on)


## Untick `mate`'s box and disable it (a dead teammate).
func disable(mate: Node) -> void:
	var box: CheckBox = _checks.get(mate.get_instance_id())
	if box != null:
		box.set_pressed_no_signal(false)
		box.disabled = true


## Dock the panel on the side of the screen away from the click it is open on (LD11), `points` the
## screen points it keeps clear of, the click first: on the left, or on the right when the click
## lies in the left half, anchored to that edge (the right one `right_clear` in) and growing away
## from it as wide as its items need, its top at `PANEL_TOP`. Docked on the right where it would
## cover the click or a selected teammate's body (within `POINT_CLEAR`), it hangs from the top of
## the screen or stands on its bottom instead, `PANEL_EDGE` from it, the side away from the centre
## of the click and those bodies first: the first of these docks that covers none of them, else the
## first that leaves the click clear, else that side away.
func dock(points: Array) -> void:
	var screen := get_viewport().get_visible_rect()
	var right: bool = points[0].x < screen.get_center().x
	# Each vertical dock as [anchor, offset, grows up]: below the timer, the top, the bottom.
	var vertical: Array = _right_dock(screen, points) if right else [0.0, PANEL_TOP, false]
	var edge := 1.0 if right else 0.0
	var gap := -(PANEL_EDGE + right_clear) if right else PANEL_EDGE
	# Pushing the opposite anchor along: a left anchor moved past the right one would be held back.
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		set_anchor_and_offset(side, edge, gap, true)
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		set_anchor_and_offset(side, vertical[0], vertical[1], true)
	grow_horizontal = (
		Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	)
	grow_vertical = (
		Control.GROW_DIRECTION_BEGIN if vertical[2] else Control.GROW_DIRECTION_END
	)


## The vertical dock (`[anchor, offset, grows up]`) of a panel docked on the right of `screen`:
## below the timer, then the top or the bottom, the side away from the centre of `points` first;
## the first that keeps clear of all `points`, else the first clear of the click (`points[0]`),
## else that side away.
func _right_dock(screen: Rect2, points: Array) -> Array:
	var extent := get_combined_minimum_size()
	extent.x = maxf(extent.x, PANEL_WIDTH)
	var top := [0.0, PANEL_EDGE, false]
	var bottom := [1.0, -PANEL_EDGE, true]
	var centre: Vector2 = points.reduce(
		func(sum, p): return sum + p,
		Vector2.ZERO,
	) / points.size()
	var away := [top, bottom] if centre.y >= screen.get_center().y else [bottom, top]
	var docks: Array = [[0.0, PANEL_TOP, false]] + away
	var clear_all := docks.filter(
		func(d: Array) -> bool: return points.all(_clear_of.bind(_dock_rect(screen, extent, d))),
	)
	var clear_click := docks.filter(
		func(d: Array) -> bool: return _clear_of(points[0], _dock_rect(screen, extent, d)),
	)
	return (clear_all[0] if not clear_all.is_empty()
			else clear_click[0] if not clear_click.is_empty()
			else away[0])


## The screen rect of a panel of `extent` docked on the right of `screen` at the vertical dock `d`
## (`[anchor, offset, grows up]`).
func _dock_rect(screen: Rect2, extent: Vector2, d: Array) -> Rect2:
	var y: float = screen.position.y + d[0] * screen.size.y + d[1]
	return Rect2(
		Vector2(
			screen.end.x - right_clear - PANEL_EDGE - extent.x,
			y - (extent.y if d[2] else 0.0),
		),
		extent,
	)


## Whether screen point `p` lies `POINT_CLEAR` or more outside screen rect `rect`.
func _clear_of(p: Vector2, rect: Rect2) -> bool:
	return not rect.grow(POINT_CLEAR).has_point(p)


## The "Teammates" heading and a box per teammate of `teammates` under `box`, ticking one calling
## `toggle(mate, on)`.
func _build_teammates(box: VBoxContainer, teammates: Array, toggle: Callable) -> void:
	var heading := _label(box, LIST_FONT)
	heading.text = "Teammates"
	_list_box = VBoxContainer.new()
	box.add_child(_list_box)
	for mate: Node in teammates:
		var check := CheckBox.new()
		check.text = String(mate.name)
		check.focus_mode = Control.FOCUS_NONE
		check.add_theme_font_size_override("font_size", LIST_FONT)
		check.toggled.connect(func(on: bool): toggle.call(mate, on))
		_list_box.add_child(check)
		_checks[mate.get_instance_id()] = check


## A new Label at font size `font_size`, added under `parent`.
func _label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
