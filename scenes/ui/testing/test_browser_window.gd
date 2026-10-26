extends CanvasLayer
## UI domain, test browser window: lists every game test grouped by domain, with a search box
## (matched by the host's `matcher`), the last result per test, and a details
## pane. Play (or double-click / Enter) emits `play_requested`; Back emits `back_requested`; Run
## all, or the ▶ button on a domain's row, emits `run_requested` and the host answers with
## `set_run_status` / `set_results`. Built in code like the other UI windows; it knows nothing of
## the Testing domain — only the descriptor dicts
## (`{ id, path, name, domain, category, description, tags, requires_von, manual, switches, world,
## locked, error }`) and the `{ id: status }` results it is handed.
## Each test (not sandbox) row has a checkbox; a domain row's box and the header's "Check shown"
## button tick or clear the tests the search currently shows. "Run N checked" emits
## `run_queue_requested` with the ticked tests' paths for a headed, one-by-one run (the host
## persists the ticks via `checked_changed`). The list itself, its rows, ticks and ▶ buttons, is
## `test_browser_list.gd` (`_tree`).

## Play the selected test or sandbox (its script path) in the runner.
signal play_requested(path: String)
## Back to the setup window.
signal back_requested
## Run the tests of `domain` — every test when it is "" (the host spawns the run and reports back
## through `set_run_status` / `set_results`).
signal run_requested(domain: String)
## Run the ticked tests one after another in the real (headed) runner: their script paths, in list
## order.
signal run_queue_requested(paths: Array)
## The set of ticked test ids changed (so the host can restore it next time).
signal checked_changed(ids: Array)
## The search text changed (so the host can restore it next time).
signal filter_changed(text: String)

const TestBrowserList := preload("res://scenes/ui/testing/test_browser_list.gd")

## The test descriptors the list shows.
var _tests: Array = []
## Hand-played sandboxes: their own section below the tests, never part of a run.
var _sandboxes: Array = []
## The host's search test: `(descriptor, text) -> bool`.
var _matcher: Callable
## The search box, the test list and the details pane.
var _search: LineEdit
var _tree: TestBrowserList
var _details: RichTextLabel
## The Play and Run all buttons, and the line under them that reports a run.
var _play: Button
var _run_all: Button
var _run_status: Label
## How many tests the search shows, of all ("shown / total").
var _count: Label
## The header's "Check shown" button and the "Run N checked" button.
var _check_shown: Button
var _run_checked: Button


## Build the window over `tests`, marking `results`, showing `state` again: its `filter` prefilled,
## its `selected` (a test path) highlighted and its `checked` (test ids) ticked (null: none of
## them). `matcher(test, text) -> bool` decides which tests a search shows.
func open(
	tests: Array,
	sandboxes: Array,
	results: Dictionary,
	matcher: Callable,
	state: TestBrowserState = null,
) -> void:
	if state == null:
		state = TestBrowserState.new()
	_tests = tests
	_sandboxes = sandboxes
	_matcher = matcher
	_build_ui()
	_tree.setup(tests, state.checked)
	_tree.results = results
	_search.text = state.filter
	_refresh(state.selected)
	_search.grab_focus()


## Lay out the header (title, search, count), the list + details split and the buttons.
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	_build_header(box)
	_build_split(box)
	_build_buttons(box)


## The header row under `box`: the title, the search, the check-shown button and the count.
func _build_header(box: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	box.add_child(header)
	var title := Label.new()
	title.text = "TESTS"
	title.add_theme_font_size_override("font_size", 56)
	header.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search tests (name, domain, tag)…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.add_theme_font_size_override("font_size", 28)
	_search.text_changed.connect(func(t: String):
		filter_changed.emit(t)
		_refresh(_selected_path()))
	_search.text_submitted.connect(func(_t): _play_selected())
	header.add_child(_search)
	_check_shown = Button.new()
	_check_shown.add_theme_font_size_override("font_size", 24)
	_check_shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_check_shown.pressed.connect(_on_check_shown)
	header.add_child(_check_shown)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 22)
	_count.modulate = Color(1, 1, 1, 0.7)
	header.add_child(_count)


## The list (a Tree, domain and topic rows over the tests) beside the details pane, under `box`.
func _build_split(box: VBoxContainer) -> void:
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	_tree = TestBrowserList.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(560, 0)
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.add_theme_font_size_override("font_size", 24)
	_tree.item_selected.connect(_show_details)
	_tree.item_activated.connect(_play_selected)
	_tree.play_requested.connect(play_requested.emit)
	_tree.run_domain.connect(run_requested.emit)
	_tree.synced.connect(_update_buttons)
	_tree.ticks_changed.connect(checked_changed.emit)
	split.add_child(_tree)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.custom_minimum_size = Vector2(480, 0)
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_theme_font_size_override("normal_font_size", 22)
	_details.add_theme_font_size_override("bold_font_size", 26)
	split.add_child(_details)


## The bottom row under `box`: Run all, the run status, Back, Run N checked and Play.
func _build_buttons(box: VBoxContainer) -> void:
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_run_all = Button.new()
	_run_all.text = "Run all"
	_run_all.add_theme_font_size_override("font_size", 28)
	_run_all.pressed.connect(run_requested.emit.bind(""))
	buttons.add_child(_run_all)
	_run_status = Label.new()
	_run_status.add_theme_font_size_override("font_size", 22)
	_run_status.modulate = Color(1, 1, 1, 0.8)
	_run_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_run_status.clip_text = true
	buttons.add_child(_run_status)
	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 28)
	back.pressed.connect(back_requested.emit)
	buttons.add_child(back)
	_run_checked = Button.new()
	_run_checked.add_theme_font_size_override("font_size", 28)
	_run_checked.pressed.connect(func(): run_queue_requested.emit(_tree.checked_paths()))
	buttons.add_child(_run_checked)
	_play = Button.new()
	_play.text = "Play"
	_play.add_theme_font_size_override("font_size", 28)
	_play.pressed.connect(_play_selected)
	buttons.add_child(_play)


## Show the host's run progress / outcome next to the buttons; `running` disables Run all and the
## domain ▶ buttons.
func set_run_status(text: String, running := false) -> void:
	_run_status.text = text
	_run_all.disabled = running
	_tree.set_running(running)
	_update_buttons()


## Replace the `{ id: status }` marks (after a run) and redraw the list.
func set_results(results: Dictionary) -> void:
	_tree.results = results
	_refresh(_selected_path())
	_show_details()


## Rebuild the list for the current search, keeping `keep` (a path) selected when it is still shown,
## else selecting the first match.
func _refresh(keep: String) -> void:
	var pick := _tree.rebuild(_search.text, _matcher, _sandboxes, keep)
	if pick != null:
		pick.select(0)
		_tree.scroll_to_item(pick)
	else:
		_details.text = "[i]No tests match.[/i]"
	_play.disabled = pick == null


## The header button: tick every shown test, or clear them when they are all ticked already.
func _on_check_shown() -> void:
	_tree.tick(_tree.test_items.keys(), not _tree.all_shown_checked())


## The header and "Run N checked" buttons' text and enabled state, and the count line.
func _update_buttons() -> void:
	_check_shown.text = "Uncheck shown" if _tree.all_shown_checked() else "Check shown"
	_check_shown.disabled = _tree.test_items.is_empty()
	_run_checked.text = "Run %d checked" % _tree.checked.size()
	_run_checked.disabled = _tree.checked.is_empty() or _tree.running
	_count.text = "%d / %d" % [_tree.shown_count, _tests.size() + _sandboxes.size()] \
		+ ("" if _tree.checked.is_empty() else "  ·  %d checked" % _tree.checked.size())


## Fill the details pane for the selected test.
func _show_details() -> void:
	var t := _selected()
	if t.is_empty():
		return
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % t["name"])
	lines.append("[color=#9aa]%s[/color]" % t["id"])
	if t.get("error", "") != "":
		lines.append("[color=#ff6a5a]Script %s[/color]" % t["error"])
	if String(t.get("description", "")) != "":
		lines.append("\n" + String(t["description"]))
	lines.append("")
	lines.append_array(_setup_lines(t))
	_details.text = "\n".join(lines)


## The details pane's lines about how test `t` runs: its world, tags, switches, locks, Von, a
## sandbox's hint and its last result.
func _setup_lines(t: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("World: %s" % t.get("world", "?"))
	if not (t.get("tags", []) as Array).is_empty():
		lines.append("Tags: %s" % ", ".join(t["tags"]))
	var switches: Dictionary = t.get("switches", {})
	if not switches.is_empty():
		var parts := PackedStringArray()
		for s in switches:
			parts.append("%s %s" % [s, "on" if switches[s] else "[color=#ff8a7a]off[/color]"])
		lines.append("Switches: %s" % ", ".join(parts))
	if not (t.get("locked", []) as Array).is_empty():
		lines.append("Locked while it runs: %s" % ", ".join(t["locked"]))
	if t.get("requires_von", false):
		lines.append("Needs the Von decision server (skipped without one).")
	if t.get("manual", false):
		lines.append("Sandbox: play it yourself (WASD, mouse, F, Space).")
	var status: String = _tree.results.get(t["id"], "")
	if status != "":
		lines.append("Last result: %s" % status)
	return lines


## Emit `play_requested` for the selected test, if any.
func _play_selected() -> void:
	var path := _selected_path()
	if path != "":
		play_requested.emit(path)


## The selected test's descriptor ({} when none).
func _selected() -> Dictionary:
	var item := _tree.get_selected()
	return item.get_metadata(0) if item != null and item.get_metadata(0) is Dictionary else {}


## The selected test's script path ("" when none).
func _selected_path() -> String:
	return String(_selected().get("path", ""))
