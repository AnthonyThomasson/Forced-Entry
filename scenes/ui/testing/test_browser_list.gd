extends Tree
## UI domain, the test browser window's list (`test_browser_window.gd`, its `_tree`): the rows (a
## row per domain, carrying a ▶ button that runs it, a row per topic folder under it, a row per test
## marked by its last result, then the sandboxes in their own section), the ticks and the partial
## state of a domain or topic row's box, the double-click and checkbox handling and the run lock on
## the ▶ buttons. The window builds and lays it out, hands it the tests, the search and the results,
## and relays what it reports: `play_requested` and `run_domain` to its own signals, `synced` to its
## buttons and `ticks_changed` to the host.

## A test's label was double-clicked: play it (its script path).
signal play_requested(path: String)
## A domain row's ▶ was clicked: run that domain's tests.
signal run_domain(domain: String)
## The boxes were brought in line with `checked` (the window redraws its buttons).
signal synced
## The ticked test ids changed (after `synced`).
signal ticks_changed(ids: Array)

const RESULT_HUD := preload("res://scenes/ui/testing/test_result_hud.gd")
const STATUS_MARKS := { "PASS": "✓", "FAIL": "✗", "TIMEOUT": "⏱", "SKIPPED": "–", "GAP": "○" }
## Side of the ▶ run button's icon on a domain row, in pixels.
const RUN_ICON_SIZE := 22

## The ▶ run button's icon, drawn once.
static var _icon_cache: Texture2D = null

## The current list's group rows: a domain row per domain (keyed by its name, each carrying a ▶
## button) and, under it, a row per sub-folder of tests the domain has (keyed "<domain>/<category>",
## no button).
var groups: Dictionary = {}
## Ticked test ids (id → true); kept across searches, and stale ids are dropped on `setup`.
var checked: Dictionary = {}
## The tick-able tests the search shows: id → its TreeItem, and group key (domain, or
## "<domain>/<category>") → [ids].
var test_items: Dictionary = {}
var _shown_by_domain: Dictionary = {}
## How many tests and sandboxes the search shows (the count line's first number).
var shown_count := 0
## The last result per test, `{ id: status }`.
var results: Dictionary = {}
## A run is going: every domain's ▶ is disabled.
var running := false
## The test descriptors, the window's own Array (every test, shown or not).
var _tests: Array = []


func _init() -> void:
	gui_input.connect(_on_tree_input)
	button_clicked.connect(_on_group_button)
	item_edited.connect(_on_item_edited)


## Take `tests` (held, not copied) and tick those of `ticked` (test ids) whose script loads.
func setup(tests: Array, ticked: Array) -> void:
	_tests = tests
	for t in tests:
		if ticked.has(t["id"]) and t.get("error", "") == "":
			checked[t["id"]] = true


## Rebuild the list for search `text` (`matcher(test, text) -> bool`) over the tests and
## `sandboxes`, and return the row to select: the one whose test or sandbox is at path `keep` when
## it is still shown, else the first match; null when nothing is shown.
func rebuild(text: String, matcher: Callable, sandboxes: Array, keep: String) -> TreeItem:
	clear()
	var root := create_item()
	groups.clear()
	test_items.clear()
	_shown_by_domain.clear()
	var shown: Array = []  # every row shown, in order: the tests, then the sandboxes
	for t in _tests:
		if matcher.call(t, text):
			shown.append(_add_test_row(root, t))
	var sandbox_group: TreeItem = null
	for t in sandboxes:
		if not matcher.call(t, text):
			continue
		if sandbox_group == null:
			sandbox_group = create_item(root)
			sandbox_group.set_text(0, "SANDBOXES  (play by hand, not tests)")
			sandbox_group.set_selectable(0, false)
			sandbox_group.set_custom_color(0, Color(0.85, 0.75, 0.5))
		var sandbox_item := create_item(sandbox_group)
		sandbox_item.set_text(0, "    " + String(t["name"]))
		sandbox_item.set_metadata(0, t)
		shown.append(sandbox_item)
	shown_count = shown.size()
	_sync_checks()
	return _pick_of(shown, keep)


## Disable (`on`) or enable every domain row's ▶ for a run going.
func set_running(on: bool) -> void:
	if on != running:
		running = on
		for g: TreeItem in groups.values():
			if g.get_button_count(0) > 0:  # a domain row has the ▶ button, a topic row does not
				g.set_button_disabled(0, 0, on)


## The row of test `t`, under its domain's row (and its topic's, when it has a `category`), each
## made under `root` the first time; a runnable test (no script error) is kept for the checks,
## shown under each of its groups.
func _add_test_row(root: TreeItem, t: Dictionary) -> TreeItem:
	var domain: String = t["domain"]
	if not groups.has(domain):
		groups[domain] = _domain_row(root, domain)
	var keys := [domain]
	var category: String = t.get("category", "")
	if category != "":
		var key := domain + "/" + category
		if not groups.has(key):
			groups[key] = _topic_row(groups[domain], category, key)
		keys.append(key)
	var item := _test_row(groups[keys[-1]], t)
	if t.get("error", "") == "":
		test_items[t["id"]] = item
		for key in keys:
			if not _shown_by_domain.has(key):
				_shown_by_domain[key] = []
			_shown_by_domain[key].append(t["id"])
	return item


## A domain's row under `root`: a checkbox over its tests and the ▶ button that runs them.
func _domain_row(root: TreeItem, domain: String) -> TreeItem:
	var g := create_item(root)
	# The mode comes first: changing a cell's mode clears its text.
	g.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	g.set_editable(0, true)
	g.set_text(0, domain.to_upper())
	g.set_selectable(0, false)
	g.set_custom_color(0, Color(0.7, 0.75, 0.85))
	g.set_metadata(0, domain)
	g.add_button(
		0,
		_run_icon(),
		0,
		running,
		"Run the %d %s tests" % [_runnable_count(domain), domain],
	)
	return g


## A topic's row (`category`, its group key `key`) under its domain's row `parent`: a checkbox.
func _topic_row(parent: TreeItem, category: String, key: String) -> TreeItem:
	var c := create_item(parent)
	c.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	c.set_editable(0, true)
	c.set_text(0, category)
	c.set_selectable(0, false)
	c.set_custom_color(0, Color(0.6, 0.65, 0.75))
	c.set_metadata(0, key)
	return c


## Test `t`'s row under `parent`: its last result's mark, name and "[Von]", coloured by that result
## (a script error red); a checkbox unless it has a script error.
func _test_row(parent: TreeItem, t: Dictionary) -> TreeItem:
	var item := create_item(parent)
	if t.get("error", "") == "":
		# before the text: a mode change clears it
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
	var status: String = results.get(t["id"], "")
	var mark: String = STATUS_MARKS.get(status, " ")
	var suffix := ""
	if t.get("requires_von", false):
		suffix += "  [Von]"
	item.set_text(0, "%s  %s%s" % [mark, t["name"], suffix])
	if RESULT_HUD.STATUS_COLORS.has(status):
		item.set_custom_color(0, RESULT_HUD.STATUS_COLORS[status])
	elif t.get("error", "") != "":
		item.set_custom_color(0, RESULT_HUD.STATUS_COLORS["FAIL"])
	item.set_metadata(0, t)
	return item


## The row to select among `shown`: the one whose test or sandbox is at path `keep`, else the
## first; null when nothing is shown.
func _pick_of(shown: Array, keep: String) -> TreeItem:
	var keep_item: TreeItem = null
	for item: TreeItem in shown:
		if (item.get_metadata(0) as Dictionary)["path"] == keep:
			keep_item = item
	if keep_item != null:
		return keep_item
	return shown[0] if not shown.is_empty() else null


## A double-click on a test's label opens it. Godot raises `item_activated` for rows without a
## checkbox (and for Enter), but not for a double-click on an editable check cell, so that case is
## handled here; on the checkbox itself a double-click just toggles.
func _on_tree_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_LEFT
				and event.pressed
				and event.double_click):
		return
	var item := get_item_at_position(event.position)
	if (item != null
			and item.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK
			and item.get_metadata(0) is Dictionary
			and not _over_checkbox(event.position, item)):
		play_requested.emit(item.get_metadata(0)["path"])


## Whether tree-local `pos` is over `item`'s checkbox (the left edge of its label cell).
func _over_checkbox(pos: Vector2, item: TreeItem) -> bool:
	var box := (get_theme_icon(&"checked").get_width()
			+ get_theme_constant(&"h_separation"))
	return pos.x < get_item_area_rect(item, 0).position.x + box


## A checkbox was toggled: a test row ticks itself, a domain or category row ticks or clears every
## shown test it holds.
func _on_item_edited() -> void:
	apply_edit(get_edited())


## Apply the new state of the checkbox on `item` (the row the user just toggled).
func apply_edit(item: TreeItem) -> void:
	if item == null:
		return
	var on := item.is_checked(0)
	if item.get_metadata(0) is Dictionary:
		tick([item.get_metadata(0)["id"]], on)
	elif item.get_metadata(0) is String:
		tick(_shown_by_domain.get(item.get_metadata(0), []), on)


## Tick or clear `ids`, redraw the boxes in place (the list keeps its scroll and selection) and tell
## the host.
func tick(ids: Array, on: bool) -> void:
	for id in ids:
		if on:
			checked[id] = true
		else:
			checked.erase(id)
	_sync_checks()
	ticks_changed.emit(checked.keys())


## Whether at least one test is shown and every shown test is ticked.
func all_shown_checked() -> bool:
	return not test_items.is_empty() and test_items.keys().all(func(id): return checked.has(id))


## Bring every checkbox and the domain and category rows' partial state in line with `checked`,
## then report `synced` (the window's buttons).
func _sync_checks() -> void:
	for id in test_items:
		(test_items[id] as TreeItem).set_checked(0, checked.has(id))
	for domain in groups:
		var ids: Array = _shown_by_domain.get(domain, [])
		var ticked := ids.filter(func(id): return checked.has(id)).size()
		var g: TreeItem = groups[domain]
		g.set_checked(0, not ids.is_empty() and ticked == ids.size())
		g.set_indeterminate(0, ticked > 0 and ticked < ids.size())
	synced.emit()


## The ticked tests' script paths in list order (including ticked tests the search hides).
func checked_paths() -> Array:
	return _tests.filter(func(t): return checked.has(t["id"])).map(func(t): return t["path"])


## A domain row's ▶ was clicked: ask the host to run that domain (ignored while a run is going).
func _on_group_button(item: TreeItem, _column: int, _id: int, mouse_button: int) -> void:
	if mouse_button == MOUSE_BUTTON_LEFT and not running and item.get_metadata(0) is String:
		run_domain.emit(item.get_metadata(0))


## How many of `domain`'s tests a run will execute, whatever the search shows.
func _runnable_count(domain: String) -> int:
	return _tests.filter(func(t): return t["domain"] == domain).size()


## The ▶ icon for a domain's run button: a green right-pointing triangle, drawn once.
static func _run_icon() -> Texture2D:
	if _icon_cache == null:
		var side := RUN_ICON_SIZE
		var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
		var color: Color = RESULT_HUD.STATUS_COLORS["PASS"]
		for y in side:
			# The triangle's right edge narrows linearly from the full width at the middle row to a
			# point at the ends.
			var reach := int(side * (1.0 - absf((y + 0.5) / side - 0.5) * 2.0))
			for x in reach:
				img.set_pixel(x, y, color)
		_icon_cache = ImageTexture.create_from_image(img)
	return _icon_cache
