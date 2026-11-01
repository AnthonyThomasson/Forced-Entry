extends CanvasLayer
## The showroom's picker: Previous / Next buttons along the bottom of the screen and a label
## `n / N   title` with one line under it. A press emits `picked(index)`; the stage stages that set.
## The buttons take no focus, so Space and Enter never press them.

signal picked(index: int)

var _count := 0
var _index := 0
var _headings: Array = []
var _lines: Array = []
var _heading: Label
var _line: Label


func _init() -> void:
	layer = 40


func _ready() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -64
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	row.add_child(_button("Previous", -1))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading = Label.new()
	_line = Label.new()
	_line.add_theme_font_size_override("font_size", 12)
	text.add_child(_heading)
	text.add_child(_line)
	row.add_child(text)
	row.add_child(_button("Next", 1))
	add_child(bar)
	_show()


## Start on set `index` of `count` sets, each with its `heading` and `line`.
func setup(count: int, headings: Array, lines: Array) -> void:
	_count = count
	_headings = headings
	_lines = lines


## Show set `index` as the current one (without emitting `picked`).
func show_index(index: int) -> void:
	_index = index
	if is_node_ready():
		_show()


func _button(label: String, step: int) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 0)
	b.pressed.connect(_step.bind(step))
	return b


func _step(step: int) -> void:
	picked.emit(posmod(_index + step, _count))


func _show() -> void:
	if _index < _headings.size():
		_heading.text = "%d / %d   %s" % [_index + 1, _count, _headings[_index]]
		_line.text = _lines[_index]
