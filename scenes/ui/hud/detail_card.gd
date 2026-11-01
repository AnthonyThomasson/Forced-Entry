extends PanelContainer
## UI hud, the detail card: the panel the spectator inspector opens for the NPC a right-click
## selected. Docked top-left under the match timer, on a dark background, it lists in fixed
## sections, always shown (an empty one says "—"), who the NPC is (name · side · rank), its health,
## its held item with the ammo and grenades, what it wears (`OutfitLines`), and the words of its
## debug overlays: the decision path (the agent label), Von's brain, the search, the entry, and the
## tactical point last clicked. The overlay words are each overlay's `card_lines()`, the same lines
## it draws (so the card never formats the controller's getters itself), read off the NPC's overlay
## children duck-typed, like `OverlayRegistry.apply`. Refreshed `REFRESH` seconds apart, also while
## the tree is paused. A dead NPC's card stays, marked dead, until `close()`. It never swallows a
## click: the right button selects through it. It is as tall as its text, never past the window's
## bottom edge (`BOTTOM` px clear): the sections scroll inside it, under the mouse wheel, which it
## swallows (the camera zooms by the wheel too, but only when no UI took it).

## Seconds between refreshes of the card's text.
const REFRESH := 0.1
## The card's width (px), shortened to clear the overlay bar's column on a narrow window.
const WIDTH := 560.0
## Its left edge and top (below the match HUD's timer: its `PANEL_TOP`), and its gap to the column
## it keeps clear.
const LEFT := 24.0
const TOP := MatchHud.PANEL_TOP
const GAP := 10.0
## The gap (px) the card keeps between its bottom edge and the window's.
const BOTTOM := 12.0
## How far (px) one wheel notch scrolls the sections.
const WHEEL_STEP := 60.0
## Font sizes of the title line, the section headings and the section bodies.
const TITLE_SIZE := 22
const HEADING_SIZE := 14
const BODY_SIZE := 18
## A police unit's rank marks (`wardrobe.rank`) by name.
const RANKS := ["trooper", "sergeant", "lead"]
## The sections after the title, in order: the heading shown, and the child of the NPC's whose
## `card_lines()` fills it (a section with no child says "—").
const OVERLAY_SECTIONS := [
	["Decision", "AgentDebug"], ["Von brain", "BrainDebug"], ["Search", "SearchDebug"],
	["Entry", "EntryDebug"],
]
const MatchHud := preload("res://scenes/ui/hud/match_hud.gd")
const OutfitLines := preload("res://scenes/ui/hud/outfit_lines.gd")
const OverlayRegistry := preload("res://scenes/ui/overlays/overlay_registry.gd")

## The NPC shown, or null while the card is closed.
var _npc: Node = null
## The tactical point shown in the Point section (`debug_zones()` entry), {} for none.
var _point: Dictionary = {}
## The screen width (px) from the right edge the card keeps clear.
var _right_clear := 0.0
## Seconds since the text was last refreshed.
var _since := 0.0
## The sections' scroll container, as tall as its text up to what the window leaves.
var _scroll: ScrollContainer
## The sections' column, inside `_scroll`.
var _box: VBoxContainer
## The title line (name · side · rank).
var _title: Label
## Each section's body label by its heading.
var _bodies: Dictionary = {}


## Refresh the text every `REFRESH` seconds while the card is open (also while the tree is paused).
func _process(delta: float) -> void:
	_since += delta
	if visible and _since >= REFRESH:
		refresh()


## Scroll the sections under the mouse wheel and swallow it; every other click passes through, to
## the inspector's right-click select.
func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var step := WHEEL_STEP * maxf(event.factor, 1.0)
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll.scroll_vertical += int(step)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll.scroll_vertical -= int(step)
		accept_event()


## Build the card, hidden, keeping `right_clear` px from the right edge clear (the overlay bar).
func setup(right_clear: float) -> void:
	_right_clear = right_clear
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.86)
	style.set_content_margin_all(10.0)
	add_theme_stylebox_override("panel", style)
	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	_title = _label(TITLE_SIZE, Color(1.0, 0.9, 0.45))
	_box.add_child(_title)
	for heading: String in _headings():
		var head := _label(HEADING_SIZE, Color(0.6, 0.75, 1.0))
		head.text = heading.to_upper()
		_box.add_child(head)
		var body := _label(BODY_SIZE, Color(1, 1, 1))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(body)
		_bodies[heading] = body
	get_viewport().size_changed.connect(_dock)


## Open the card for `npc`: its sections filled now and kept fresh, no tactical point yet.
func show_for(npc: Node) -> void:
	_npc = npc
	_point = {}
	_dock()
	visible = true
	refresh()


## Close the card.
func close() -> void:
	_npc = null
	_point = {}
	visible = false


## Show `zone` (a `debug_zones()` entry: `category`, `label`, `desc`) in the Point section; {}
## clears it.
func set_point(zone: Dictionary) -> void:
	_point = zone
	if visible:
		refresh()


## Fill every section from the NPC now. A freed NPC closes the card.
func refresh() -> void:
	_since = 0.0
	if _npc == null:
		return
	if not is_instance_valid(_npc):
		close()
		return
	_title.text = _title_text()
	_bodies["Health"].text = _health_text()
	_bodies["Item"].text = "\n".join([_item_text(), _grenade_text()])
	_bodies["Outfit"].text = _or_dash(OutfitLines.of(_npc.wardrobe.outfit.view()))
	for section: Array in OVERLAY_SECTIONS:
		_bodies[section[0]].text = _or_dash(_overlay_lines(section[1]))
	_bodies["Point"].text = _point_text()
	_fit()


## Every section heading, in order.
func _headings() -> Array[String]:
	var out: Array[String] = ["Health", "Item", "Outfit"]
	for section: Array in OVERLAY_SECTIONS:
		out.append(section[0])
	out.append("Point")
	return out


## A label that never swallows a click.
func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Place the card top-left, its width what the window leaves beside the column it keeps clear.
func _dock() -> void:
	var room := get_viewport_rect().size.x - _right_clear - GAP - LEFT
	offset_left = LEFT
	offset_right = LEFT + minf(WIDTH, maxf(room, 0.0))
	offset_top = TOP
	offset_bottom = TOP
	_fit()


## Make the sections as tall as their text, up to the window's bottom edge less `BOTTOM`: past it
## they scroll. Run on each refresh and, by `_dock`, when the window is resized.
func _fit() -> void:
	if _scroll == null:
		return
	var panel := get_theme_stylebox("panel")
	var chrome := panel.get_minimum_size().y
	var room := get_viewport_rect().size.y - TOP - BOTTOM - chrome
	_scroll.custom_minimum_size.y = clampf(_box.get_combined_minimum_size().y, 0.0, maxf(room, 0.0))


## "name · side · rank", marked dead once the NPC is.
func _title_text() -> String:
	var side := OverlayRegistry.side_of(_npc.faction)
	var rank := "—"
	if _npc.faction == &"invader":
		rank = RANKS[clampi(_npc.wardrobe.rank, 0, RANKS.size() - 1)]
	var text := "%s · %s · %s" % [_npc.name, side, rank]
	return text + " · DEAD" if _npc.is_dead else text


## "42 / 50", or "dead".
func _health_text() -> String:
	if _npc.is_dead:
		return "dead"
	return "%d / %d" % [roundi(_npc.health), roundi(_npc.max_health)]


## "Pistol · 7/12  (+2 mags)  reloading…": the held item and its ammo ("—" for an item without),
## "—" alone for a hand holding nothing.
func _item_text() -> String:
	if _npc.inventory.current_item() == null:
		return "—"
	var rounds: int = _npc.ammo.rounds()
	var ammo := "—"
	if rounds >= 0:
		ammo = ("%d/%d  (+%d mags)"
				% [rounds, _npc.ammo.capacity(), _npc.ammo.spare_magazines()])
		if _npc.ammo.is_reloading():
			ammo += "  reloading…"
	return "%s · %s" % [_npc.inventory.item_name(), ammo]


## "Grenades: 1 stun, 2 frag" for what is carried, "Grenades: —" with none.
func _grenade_text() -> String:
	var carried := []
	for option: Dictionary in LoadoutConfig.grenade_options():
		var count: int = _npc.inventory.item_count(option["slot"])
		if count > 0:
			carried.append("%d %s" % [count, option["id"]])
	return "Grenades: %s" % (", ".join(carried) if not carried.is_empty() else "—")


## The `card_lines()` of the NPC's child `child_name`, none if it has no such child.
func _overlay_lines(child_name: String) -> Array:
	var overlay := _npc.get_node_or_null(child_name)
	if overlay == null or not overlay.has_method(&"card_lines"):
		return []
	return Array(overlay.card_lines())


## "CATEGORY · label" and the reasoning text of the clicked point; "—" with none.
func _point_text() -> String:
	if _point.is_empty():
		return "—"
	var label: String = _point.get("label", "")
	var desc: String = _point.get("desc", "")
	return "%s%s%s" % [
		String(_point["category"]).to_upper(),
		"  ·  " + label if label != "" else "",
		"\n" + desc if desc != "" else "",
	]


## `lines` joined by newlines, or "—" when there are none.
func _or_dash(lines: Array) -> String:
	return "\n".join(lines) if not lines.is_empty() else "—"
