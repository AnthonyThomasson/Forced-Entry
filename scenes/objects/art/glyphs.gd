extends RefCounted
## A small pixel font for the tower's painted text (Objects domain, private): the Latin capitals and
## digits on a 5 x 7 grid (`#` is paint) drawn at a whole-number scale on a `PixelCanvas`, and a few
## Chinese characters kept as brush strokes on a 0..10 grid. Read by the menu board, the hanging
## sign and the lobby's floor stencil.

const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const COLS := 5
const ROWS := 7
## Columns of one glyph plus the gap after it, in glyph pixels.
const ADVANCE := 6
const FONT := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".####", "#....", "#....", "#.###", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
}
## Chinese characters as brush strokes: each stroke a polyline of points on a 0..10 grid.
const HANZI := {
	"口": [[[2, 2], [8, 2], [8, 8], [2, 8], [2, 2]]],
	"中": [[[1, 3], [9, 3], [9, 7], [1, 7], [1, 3]], [[5, 0], [5, 10]]],
	"大": [[[0, 3], [10, 3]], [[5, 3], [1, 10]], [[5, 3], [9, 10]]],
	"工": [[[1, 1], [9, 1]], [[5, 1], [5, 9]], [[0, 9], [10, 9]]],
	"入": [[[4, 0], [1, 10]], [[3, 3], [9, 10]]],
	"出": [[[2, 0], [2, 4], [8, 4], [8, 0]], [[5, 0], [5, 10]], [[1, 5], [1, 10], [9, 10], [9, 5]]],
	"日": [[[2, 0], [8, 0], [8, 10], [2, 10], [2, 0]], [[2, 5], [8, 5]]],
	"田": [[[1, 1], [9, 1], [9, 9], [1, 9], [1, 1]], [[1, 5], [9, 5]], [[5, 1], [5, 9]]],
	"王": [[[1, 1], [9, 1]], [[2, 5], [8, 5]], [[0, 9], [10, 9]], [[5, 1], [5, 9]]],
	"品": [
		[[3, 0], [7, 0], [7, 4], [3, 4], [3, 0]],
		[[0, 6], [4, 6], [4, 10], [0, 10], [0, 6]],
		[[6, 6], [10, 6], [10, 10], [6, 10], [6, 6]],
	],
}


## Width in px of `text` at glyph `scale` (a space is a glyph too).
static func text_width(text: String, scale: int) -> int:
	return maxi(0, text.length() * ADVANCE - 1) * scale


## Height in px of one line at `scale`.
static func text_height(scale: int) -> int:
	return ROWS * scale


## Draw `text` with its top-left at `at`: each glyph pixel an `ink.width` px block of `ink.col`.
## With `ink.stencil` the middle of every stem is bridged out, so round letters read as cut from a
## stencil.
static func draw(c: PixelCanvas, text: String, at: Vector2i, ink: Dictionary) -> void:
	var scale: int = ink["width"]
	for i in text.length():
		_glyph(c, FONT.get(text[i], []), at + Vector2i(i * ADVANCE * scale, 0), ink)


## `draw`n so the text is centred on x = `centre_x`, its top at `top`.
static func draw_centered(
	c: PixelCanvas,
	text: String,
	centre_x: int,
	top: int,
	ink: Dictionary,
) -> void:
	var left := centre_x - int(text_width(text, ink["width"]) / 2.0)
	draw(c, text, Vector2i(left, top), ink)


## `text` stacked one letter under the next (a vertical sign), centred on x = `centre_x`.
static func draw_stacked(
	c: PixelCanvas,
	text: String,
	centre_x: int,
	top: int,
	ink: Dictionary,
) -> void:
	var scale: int = ink["width"]
	for i in text.length():
		var at := Vector2i(centre_x - int(COLS * scale / 2.0), top + i * (ROWS + 2) * scale)
		draw(c, text[i], at, ink)


## The Chinese character `ch` as brush strokes in the `size` px box at `at`, painted with `ink`.
static func draw_hanzi(
	c: PixelCanvas,
	ch: String,
	at: Vector2i,
	size: int,
	ink: Dictionary,
) -> void:
	var step := size / 10.0
	for stroke: Array in HANZI.get(ch, []):
		for k in stroke.size() - 1:
			var a: Array = stroke[k]
			var b: Array = stroke[k + 1]
			var from := at + Vector2i((Vector2(a[0], a[1]) * step).round())
			var to := at + Vector2i((Vector2(b[0], b[1]) * step).round())
			Kit.stroke(c, from, to, ink)


## One glyph (`rows`: its 5 x 7 pattern) with its top-left at `at`, drawn with `ink`.
static func _glyph(c: PixelCanvas, rows: Array, at: Vector2i, ink: Dictionary) -> void:
	var scale: int = ink["width"]
	for gy in rows.size():
		for gx in COLS:
			var bridge: bool = ink["stencil"] and gy == 3 and gx in [0, COLS - 1]
			if rows[gy][gx] == "#" and not bridge:
				_block(c, at + Vector2i(gx * scale, gy * scale), scale, ink["col"])


## A `size` px square of `col` with its top-left at `at`.
static func _block(c: PixelCanvas, at: Vector2i, size: int, col: Color) -> void:
	for dy in size:
		for dx in size:
			c.px(at.x + dx, at.y + dy, col)
