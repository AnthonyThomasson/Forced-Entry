class_name ObjectArtStencilConfig
## The floor stencil (stencil_painter.gd, laid by `DecalFactory`): a hazard border of yellow and
## black stripes round the room and lines of text in pixel stencil letters inside it, worn. The
## colours are as drawn: the stencil painter is `ObjectArt.AS_GIVEN`. A `class_name` holder of
## `static var`s, read as `ObjectArtStencilConfig.<name>`; there is no instance and no autoload. A
## stencil's `opts` override a painter knob for that stencil only, keyed by the knob's name without
## its painter prefix (`stencil_border_px` -> `border_px`).

## The hazard stripes' two colours, the border's thickness and its stripes' width (px).
static var stencil_hazard_color: Color = Color(0.96, 0.76, 0.12)
static var stencil_hazard_black: Color = Color(0.06, 0.06, 0.07)
static var stencil_border_px: int = 12
static var stencil_stripe_px: int = 7
## The letters' paint, the largest scale (px per glyph pixel) they are drawn at and the gap between
## lines in glyph pixels.
static var stencil_paint_color: Color = Color(0.88, 0.86, 0.76)
static var stencil_text_scale: int = 3
static var stencil_line_gap: int = 2
## How far the text keeps from the border (px), how opaque the whole stencil is and how worn: the
## chance a pixel is rubbed, how deep and how many scratches.
static var stencil_text_margin: int = 8
static var stencil_opacity: float = 0.92
static var stencil_wear_chance: float = 0.2
static var stencil_wear_depth: float = 0.9
static var stencil_wear_scratches: int = 16
