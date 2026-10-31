extends GameTest
## The overlay bar's bulk buttons: a group header flips just its group, "All" flips everything, each
## flag changed emits its own `overlay_toggled`, and the counts on the buttons follow the flags.

const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
const Registry := preload("res://scenes/ui/overlays/overlay_registry.gd")
const SCRATCH := "user://overlay_toggles_test_settings.json"

var _bar: CanvasLayer
var _events: Array = []


func describe() -> Dictionary:
	return {
		"name": "Overlay bar flips a group or everything at once",
		"description": "A group header turns its whole group on (then off); All covers every "
			+ "overlay; one overlay_toggled per flag changed; counts follow the flags.",
		"tags": ["overlays", "ui"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"overlay_scopes", { "play": "all", "watch": "selected" })


func run(t: TestContext) -> void:
	_bar = OverlayToggles.new()
	t.world.add_child(_bar)
	_bar.overlay_toggled.connect(func(flag, on): _events.append([flag, on]))
	_bar.setup({})

	var perception: Array = []
	for e in Registry.ENTRIES:
		if e["group"] == "Perception":
			perception.append(e["flag"])
	var total: int = Registry.ENTRIES.size()

	t.expect_eq(_label("All"), "All (0/%d)" % total, "starts with everything off")
	t.expect_eq(
		_label("Perception"),
		"Perception (0/%d)" % perception.size(),
		"group count starts at 0",
	)
	_check_group_header(t, perception, total)
	_check_all(t, total)
	_bar.queue_free()
	_check_scope_row(t)
	_check_scope_saved(t)


## A group header turns on just its group (`perception`, of `total` overlays); pressed again, all
## on → all off; mixed → all on, only the missing flags emit.
func _check_group_header(t: TestContext, perception: Array, total: int) -> void:
	_button("Perception").pressed.emit()
	t.expect_eq(_events.size(), perception.size(), "one event per flag in the group")
	for ev in _events:
		t.check(perception.has(ev[0]) and ev[1], "%s turned on and belongs to the group" % ev[0])
	t.expect_eq(
		_label("All"),
		"All (%d/%d)" % [perception.size(), total],
		"All counts the group's flags",
	)

	# Pressed again, all on → all off.
	_events.clear()
	_button("Perception").pressed.emit()
	t.expect_eq(_events.size(), perception.size(), "turning the group off emits per flag")
	t.expect_eq(_label("All"), "All (0/%d)" % total, "back to none")

	# Mixed → all on, only the missing flags emit.
	_flag_button(perception[0]).button_pressed = true
	t.expect_eq(
		_label("Perception"),
		"Perception (1/%d)" % perception.size(),
		"a flag's own button refreshes the count",
	)
	_events.clear()
	_button("Perception").pressed.emit()
	t.expect_eq(_events.size(), perception.size() - 1, "only flags that were off emit")


## All turns every overlay (`total`) on, then off.
func _check_all(t: TestContext, total: int) -> void:
	_events.clear()
	_button("All").pressed.emit()
	t.expect_eq(_label("All"), "All (%d/%d)" % [total, total], "All turns everything on")
	_button("All").pressed.emit()
	t.expect_eq(_label("All"), "All (0/%d)" % total, "All again turns everything off")


## The "Show on" row: it offers the scopes the bar was given (no `selected` unless given), starts on
## the scope handed in, and pressing another emits `scope_changed` with it and leaves only it
## chosen.
func _check_scope_row(t: TestContext) -> void:
	_bar = OverlayToggles.new()
	t.world.add_child(_bar)
	var scopes: Array = []
	_bar.scope_changed.connect(func(scope): scopes.append(scope))
	_bar.setup({}, "all", ["defenders", "invaders", "all"])
	t.check(_has_label("Show on"), "the bar has a Show on row")
	t.expect_eq(_scope_names(), ["Defenders", "Invaders", "All"], "the row offers the given scopes")
	t.check(_scope_button("Selected") == null, "no Selected when it was not given")
	t.check(_scope_button("All").button_pressed, "the scope handed in starts chosen")
	_scope_button("Invaders").button_pressed = true
	t.expect_eq(scopes, ["invaders"], "choosing Invaders emits scope_changed(invaders)")
	t.check(not _scope_button("All").button_pressed, "only one scope stays chosen")
	_bar.queue_free()

	_bar = OverlayToggles.new()
	t.world.add_child(_bar)
	_bar.setup({}, "selected", ["selected", "defenders", "invaders", "all"])
	t.check(_scope_button("Selected") != null, "Selected is offered when given")
	t.check(_scope_button("Selected").button_pressed, "and starts chosen when handed in")
	_bar.queue_free()


## The chosen scope, saved through `Settings`, comes back from the file on a fresh launch and a
## fresh bar starts on it.
func _check_scope_saved(t: TestContext) -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.set_overlay_scope("watch", "invaders")
	Settings.overlay_scopes = { "play": "all", "watch": "selected" }
	Settings.load_file()
	t.expect_eq(Settings.overlay_scopes["watch"], "invaders", "the saved scope is read back")
	t.expect_eq(Settings.overlay_scopes["play"], "all", "the other mode keeps its own")
	_bar = OverlayToggles.new()
	t.world.add_child(_bar)
	_bar.setup({}, Settings.overlay_scopes["watch"], ["selected", "defenders", "invaders", "all"])
	t.check(_scope_button("Invaders").button_pressed, "a fresh bar starts on the saved scope")
	_bar.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## Whether the bar shows a label reading exactly `text`.
func _has_label(text: String) -> bool:
	for l in _bar.find_children("*", "Label", true, false):
		if (l as Label).text == text:
			return true
	return false


## The scope radio buttons' texts, in order.
func _scope_names() -> Array:
	var out: Array = []
	for b in _bar.find_children("*", "Button", true, false):
		if (b as Button).toggle_mode and (b as Button).button_group != null:
			out.append((b as Button).text)
	return out


## The scope radio button reading `text`, or null.
func _scope_button(text: String) -> Button:
	for b in _bar.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).button_group != null:
			return b
	return null


func _button(prefix: String) -> Button:
	for b in _bar.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix + " ("):
			return b
	return null


## The toggle button of `flag`, found by its registry label.
func _flag_button(flag: String) -> Button:
	var label := ""
	for e in Registry.ENTRIES:
		if e["flag"] == flag:
			label = e["label"]
	for b in _bar.find_children("*", "Button", true, false):
		if (b as Button).text == label:
			return b
	return null


func _label(prefix: String) -> String:
	var b := _button(prefix)
	return b.text if b != null else ""
