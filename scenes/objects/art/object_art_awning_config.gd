class_name ObjectArtAwningConfig
## What hangs over a tower's front door (awning_painter.gd): the dark awning (its stripes, scalloped
## front edge, board and neon edge) and the hanging vertical glyph sign (its board, frame and the
## ink of its two characters). The colours are as drawn: the awning painter is `ObjectArt.AS_GIVEN`.
## A `class_name` holder of `static var`s, read as `ObjectArtAwningConfig.<name>`; there is no
## instance and no autoload. A piece's catalogue `art_opts` overrides a painter knob for that piece
## only, keyed by the knob's name without its painter prefix (`awning_stripe_px` -> `stripe_px`).

## The awning's two stripe colours, how wide a stripe and a scallop of its front edge are (art px),
## how far the scallops hang below the cloth, and the board it hangs from along the wall.
static var awning_stripes: Array[Color] = [Color(0.1, 0.34, 0.36), Color(0.07, 0.07, 0.1)]
static var awning_stripe_px: int = 8
static var awning_scallop_px: int = 12
static var awning_scallop_drop: int = 6
static var awning_board_color: Color = Color(0.09, 0.09, 0.12)
## The neon along the scalloped front edge (glowing).
static var awning_edge_color: Color = Color(0.15, 0.92, 1.0)
## The hanging sign: its board, the frame and the two characters' ink (all glowing but the board).
static var hanging_board_color: Color = Color(0.09, 0.09, 0.12)
static var hanging_frame_color: Color = Color(1.0, 0.72, 0.2)
static var hanging_ink_colors: Array[Color] = [Color(0.15, 0.92, 1.0), Color(1.0, 0.2, 0.72)]
static var hanging_characters: Array[String] = ["王", "大"]
