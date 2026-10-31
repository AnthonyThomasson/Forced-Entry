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
## click: the right button selects through it.

## Seconds between refreshes of the card's text.
const REFRESH := 0.1
## The card's width (px), shortened to clear the overlay bar's column on a narrow window.
const WIDTH := 560.0
## Its left edge and top (below the match HUD's timer), and its gap to the column it keeps clear.
const LEFT := 24.0
const TOP := 76.0
const GAP := 10.0
## Font sizes of the title line, the section headings and the section bodies.
const TITLE_SIZE := 22
const HEADING_SIZE := 14
const BODY_SIZE := 18
## A police unit's rank marks (`wardrobe.rank`) by name.
const RANKS := ["trooper", "sergeant", "lead"]
## The word for each faction's side.
const SIDES := { &"household": "defender", &"invader": "invader" }
## The sections after the title, in order: the heading shown, and the child of the NPC's whose
## `card_lines()` fills it (a section with no child says "—").
const OVERLAY_SECTIONS := [
	["Decision", "AgentDebug"], ["Von brain", "BrainDebug"], ["Search", "SearchDebug"],
	["Entry", "EntryDebug"],
]
const OutfitLines := preload("res://scenes/ui/hud/outfit_lines.gd")

## The NPC shown, or null while the card is closed.
var _npc: Node = null
## The tactical point shown in the Point section (`debug_zones()` entry), {} for none.
var _point: Dictionary = {}
## The screen width (px) from the right edge the card keeps clear.
var _right_clear := 0.0
## Seconds since the text was last refreshed.
var _since := 0.0
## The title line (name · side · rank).
var _title: Label
## Each section's body label by its heading.
var _bodies: Dictionary = {}


## Refresh the text every `REFRESH` seconds while the card is open (also while the tree is paused).
func _process(delta: float) -> void:
	_since += delta
	if visible and _since >= REFRESH:
		refresh()


## Build the card, hidden, keeping `right_clear` px from the right edge clear (the overlay bar).
func setup(right_clear: float) -> void:
	_right_clear = right_clear
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.86)
	style.set_content_margin_all(10.0)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = _label(TITLE_SIZE, Color(1.0, 0.9, 0.45))
	box.add_child(_title)
	for heading: String in _headings():
		var head := _label(HEADING_SIZE, Color(0.6, 0.75, 1.0))
		head.text = heading.to_upper()
		box.add_child(head)
		var body := _label(BODY_SIZE, Color(1, 1, 1))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(body)
		_bodies[heading] = body


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


## "name · side · rank", marked dead once the NPC is.
func _title_text() -> String:
	var side: String = SIDES.get(_npc.faction, str(_npc.faction))
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


## "Pistol · 7/12  (+2 mags)  reloading…": the held item and its ammo ("—" for an item without).
func _item_text() -> String:
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
