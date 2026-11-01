class_name ObjectArtCrossingConfig
## A junction arm's crossing (crossing_painter.gd, laid by street_marks.gd): worn white zebra bars
## across the road with a stop line across the approaching lane. The colours are as drawn: the
## painter is `ObjectArt.AS_GIVEN`. A `class_name` holder of `static var`s, read as
## `ObjectArtCrossingConfig.<name>`; there is no instance and no autoload. A mark's `opts` override
## a painter knob for that mark only, keyed by the knob's name without its painter prefix
## (`crossing_bar_px` -> `bar_px`).

## The paint, and how opaque it is before it is worn.
static var crossing_color: Color = Color(0.92, 0.91, 0.86)
static var crossing_opacity: float = 0.6
## The bars: their width and the step between their centres (px), the gap kept clear between the
## junction and the bars and between the bars and the stop line, and the stop line's thickness.
static var crossing_bar_px: int = 8
static var crossing_step_px: int = 14
static var crossing_gap_px: int = 12
static var crossing_line_px: int = 4
## How worn: the chance a pixel is rubbed, how deep, how many scratches, and the share of the bars'
## pixels in the two tyre tracks rubbed clean through.
static var crossing_wear_chance: float = 0.4
static var crossing_wear_depth: float = 1.0
static var crossing_wear_scratches: int = 28
static var crossing_track_rub: float = 0.45
