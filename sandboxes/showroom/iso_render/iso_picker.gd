extends CanvasLayer
## Spike of #193's showroom: the on-screen Previous / Next buttons and the label naming the set
## shown
## (`n / N   title` and one line). Emits `picked(index)`; the stage stages that set. The
## buttons take no focus, so Space and Enter (Interact) never press them.

signal picked(index: int)

var _titles: Array[String] = []
var _notes: Array[String] = []
var _index := 0
var _label := Label.new()


func _init() -> void:
	layer = 50


func setup(titles: Array[String], notes: Array[String]) -> void:
	_titles = titles
	_notes = notes
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -64.0
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	var previous := Button.new()
	previous.text = "◀ Previous"
	previous.focus_mode = Control.FOCUS_NONE
	previous.pressed.connect(func() -> void: step(-1))
	var next := Button.new()
	next.text = "Next ▶"
	next.focus_mode = Control.FOCUS_NONE
	next.pressed.connect(func() -> void: step(1))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(640, 0)
	row.add_child(previous)
	row.add_child(_label)
	row.add_child(next)
	add_child(panel)
	show_index(0)


## Move the picker by `delta` sets (wrapping) and announce it.
func step(delta: int) -> void:
	show_index(wrapi(_index + delta, 0, _titles.size()))
	picked.emit(_index)


## Show set `index` in the label without announcing it.
func show_index(index: int) -> void:
	_index = index
	_label.text = "%d / %d   %s\n%s" % [index + 1, _titles.size(), _titles[index], _notes[index]]
