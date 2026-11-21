extends GameTest
## D21 unbake (#194 17g, `docs/stacked-items.md` SI13): the item that replaced a painted prop keeps
## the prop's look: its size and its colours (`props.gd`, the prop palette
## `ObjectArtDecorConfig.prop_colors`), not the run-down grade the catalogue colour gets. Each
## kind is painted as the old prop was (on a table-brown ground) and as the item (on its own
## canvas of its footprint): the drawn area is as wide and as deep within 3 px and its mean colour
## within 0.1 a channel. A monitor's lit screen edge is drawn glowing, in the screen's green or its
## neon, as the prop's was. The reused catalogue kinds (a book, a mug and a bowl) take the old
## prop's size, orientation and palette colour from the `carries` rows that set them, and draw in
## that colour as given (`plain`, not the run-down grade the mesh grades a catalogue colour to).

const Props := preload("res://scenes/objects/art/props.gd")
const ItemPainter := preload("res://scenes/objects/art/item_painter.gd")
const Decay := preload("res://scenes/objects/art/decay.gd")
const KINDS := [
	"monitor", "keyboard", "papers", "clock", "vase", "fruit_bowl", "cutting_board", "tools",
	"vise",
]
## The reused kinds: their old prop's name, and the piece rows that carry them (piece, key).
const REUSED := {
	"book": "book", "cup": "mug", "bowl": "bowl",
}
const CARRIERS := ["side_table", "nightstand", "dresser", "desk", "console_table"]
const GROUND := Color(0.3, 0.2, 0.1)
## How far (px) the item's drawn width or depth may differ from the prop's.
const SIZE_SLACK := 3
## How far a mean colour channel may differ.
const COLOUR_SLACK := 0.1


func describe() -> Dictionary:
	return {
		"name": "A home item keeps the look of the prop it replaced",
		"description": "Each of the monitor, keyboard, papers, clock, vase, fruit bowl, cutting "
			+ "board, tools and vise paints as big and as bright as its old prop; the monitor's "
			+ "screen edge glows, in the screen green or its neon.",
		"tags": ["objects", "art", "items", "unbake"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	for kind: String in KINDS:
		var def := ObjectDefinitions.get_definition(kind)
		var size := Vector2i(def["size"])
		var old := _old(kind)
		var item := _item(kind, size, def["color"], {})
		var gap := Vector2i(item["size"]) - Vector2i(old["size"])
		t.check(
			absi(gap.x) <= SIZE_SLACK and absi(gap.y) <= SIZE_SLACK,
			"%s is as big as its prop (%v against %v)" % [kind, item["size"], old["size"]],
		)
		for channel in 3:
			var diff := absf(float(item["mean"][channel]) - float(old["mean"][channel]))
			t.check(
				diff <= COLOUR_SLACK,
				"%s's colour channel %d is its prop's (%.2f against %.2f)" % [
					kind, channel, item["mean"][channel], old["mean"][channel],
				],
			)
	_check_glow(t)
	_check_reused(t)


## Every carried book, mug and bowl is as big, as turned and as bright as the prop it replaced.
func _check_reused(t: TestContext) -> void:
	var seen := {}
	for piece: String in CARRIERS:
		var definition := ObjectDefinitions.get_definition(piece)
		for row: Dictionary in definition.get("carries", []):
			var kind: String = row["key"]
			if not REUSED.has(kind):
				continue
			seen[kind] = true
			var item := PieceCarries.patched(
				ObjectDefinitions.get_definition(kind), PieceCarries.patch_of(row)
			)
			var old := _old(REUSED[kind])
			var size := Vector2i(item["size"])
			var gap := size - Vector2i(old["size"])
			var where := "%s's %s" % [piece, kind]
			t.check(
				absi(gap.x) <= SIZE_SLACK and absi(gap.y) <= SIZE_SLACK,
				"%s is as big as its prop (%v against %v)" % [where, size, old["size"]],
			)
			t.check(
				(size.x >= size.y) == (old["size"].x >= old["size"].y),
				"%s lies the way its prop did (%v against %v)" % [where, size, old["size"]],
			)
			t.check(
				_palette_gap(kind, item["color"]) <= COLOUR_SLACK,
				"%s is a palette colour of its prop (%s)" % [where, item["color"].to_html(false)],
			)
			t.check(
				bool(item["art_opts"].get("plain", false)),
				"%s is drawn in its own colour, not graded" % where,
			)
	for kind: String in REUSED:
		t.check(seen.has(kind), "premise: a home top carries a %s" % kind)


## How far `colour` is from the nearest colour its prop `kind` is drawn in: the books' palette
## list, else the ceramic of a mug and a bowl.
func _palette_gap(kind: String, colour: Color) -> float:
	var palette: Dictionary = ObjectArtDecorConfig.prop_colors
	var options: Array = palette["books"] if kind == "book" else [palette["ceramic"]]
	var best := 9.0
	for option: Color in options:
		best = minf(best, _off(colour, option))
	return best


## The monitor's screen edge is drawn glowing in the screen green, or in the piece's neon.
func _check_glow(t: TestContext) -> void:
	var def := ObjectDefinitions.get_definition("monitor")
	for opts: Dictionary in [{}, { "neon": "cyan" }, { "neon": "magenta" }]:
		var lit := _item("monitor", Vector2i(def["size"]), def["color"], opts)
		var mark: Image = lit["emissive"]
		var want := Decay.screen_color(opts)
		if not t.require(mark != null, "the monitor draws a glowing edge (%s)" % opts):
			continue
		var count := _glowing(mark, want)
		var seen: int = count.x
		var wrong: int = count.y
		t.check(seen >= 8, "the lit edge is %d px wide or more (%d)" % [8, seen])
		t.expect_eq(wrong, 0, "every glowing pixel is the screen colour %s" % want)


## How many pixels of `mark` glow, and how many of them are not `want`.
func _glowing(mark: Image, want: Color) -> Vector2i:
	var seen := 0
	var wrong := 0
	for y in mark.get_height():
		for x in mark.get_width():
			var p := mark.get_pixel(x, y)
			if p.a > 0.0:
				seen += 1
				wrong += 1 if _off(p, want) > 0.02 else 0
	return Vector2i(seen, wrong)


## The old prop `kind` drawn on a ground: `{ size, mean }` of what it changed.
func _old(kind: String) -> Dictionary:
	var bare := _ground()
	var c := _ground()
	Props.draw(c, kind, Vector2i(24, 24))
	return _measure(c, bare)


## A canvas of the ground alone.
func _ground() -> PixelCanvas:
	var c := PixelCanvas.new(48, 48, 7, ArtCanvasConfig.light_from)
	c.fill(PixelShape.rounded(Rect2i(0, 0, 48, 48), 0), GROUND, 0)
	return c


## The item `kind` painted alone on a canvas of its footprint `size`: `{ size, mean, emissive }`.
func _item(kind: String, size: Vector2i, colour: Color, opts: Dictionary) -> Dictionary:
	var c := PixelCanvas.new(size.x, size.y, 7, ArtCanvasConfig.light_from)
	ItemPainter.paint(c, Decay.grade(colour), "", opts.merged({ "kind": kind }))
	var out := _measure(c, null)
	out["emissive"] = c.emissive()
	return out


## The bounding size and mean colour of what `c` drew: its covered pixels, or (`bare` the same
## canvas before) the ones that differ from `bare`.
func _measure(c: PixelCanvas, bare: PixelCanvas) -> Dictionary:
	var low := Vector2i(c.w, c.h)
	var high := Vector2i(-1, -1)
	var sum := Vector3.ZERO
	var count := 0
	for y in c.h:
		for x in c.w:
			var p := c.at(x, y)
			if c.covered(x, y) if bare == null else p != bare.at(x, y):
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
				sum += Vector3(p.r, p.g, p.b)
				count += 1
	var mean := sum / float(maxi(count, 1))
	return { "size": high - low + Vector2i.ONE, "mean": [mean.x, mean.y, mean.z] }


## The largest difference of a channel between `a` and `b`.
func _off(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
