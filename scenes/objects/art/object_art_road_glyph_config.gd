class_name ObjectArtRoadGlyphConfig
## The lane marking on a road's approach to a junction (road_glyph_painter.gd, laid by
## street_marks.gd): a two-digit lane number and an ahead arrow, faded and worn. The colours are as
## drawn: the painter is `ObjectArt.AS_GIVEN`. A `class_name` holder of `static var`s, read as
## `ObjectArtRoadGlyphConfig.<name>`; there is no instance and no autoload. A mark's `opts` override
## a painter knob for that mark only, keyed by the knob's name without its painter prefix
## (`glyph_digit_scale` -> `digit_scale`).

## The paint, how big a digit's pixel is, and how opaque the marking is before it is worn.
static var glyph_color: Color = Color(0.86, 0.84, 0.74)
static var glyph_digit_scale: int = 5
static var glyph_opacity: float = 0.9
## The arrow: the half-width of its head, the shaft's width and length (px) and the gap between the
## number and the arrow.
static var glyph_arrow_head: int = 26
static var glyph_arrow_shaft_w: int = 13
static var glyph_arrow_shaft_h: int = 46
static var glyph_gap_px: int = 14
## How worn: the chance a pixel is rubbed, how deep, how many scratches.
static var glyph_wear_chance: float = 0.18
static var glyph_wear_depth: float = 0.9
static var glyph_wear_scratches: int = 10
