extends Node2D
## A caption painted on the showroom floor under an exhibit: its name and variant letter, then a
## line on how it differs, wrapped to the exhibit's width. Drawn outlined and rasterised larger,
## so it stays crisp at game zoom.

const SHARP := 2.0
const TITLE := Color(0.95, 0.92, 0.82)
const NOTE := Color(0.76, 0.78, 0.74)
## The wrap width (px) and the sizes of the title and the note.
const WIDTH := 300.0
const TITLE_SIZE := 11
const NOTE_SIZE := 8

var _title := ""
var _note := ""


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / SHARP)
	_say(font, _title, Vector2.ZERO, TITLE_SIZE, TITLE)
	_say(font, _note, Vector2(0, (TITLE_SIZE + 4) * SHARP), NOTE_SIZE, NOTE)
	draw_set_transform(Vector2.ZERO)


## Caption an exhibit: `title` (its name and letter) and `note` (how it differs), the text's
## top-left at this node.
func setup(title: String, note: String) -> void:
	_title = title
	_note = note
	z_index = DrawLayers.BLOOD
	queue_redraw()


func _say(font: Font, text: String, at: Vector2, size: int, col: Color) -> void:
	var big := roundi(size * SHARP)
	var base := at + Vector2(0, big)
	var width := WIDTH * SHARP
	draw_multiline_string_outline(
		font, base, text, HORIZONTAL_ALIGNMENT_LEFT, width, big, -1, roundi(3 * SHARP),
		Color(0, 0, 0, 0.85),
	)
	draw_multiline_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, width, big, -1, col)
