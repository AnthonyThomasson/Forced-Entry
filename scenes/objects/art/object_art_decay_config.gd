class_name ObjectArtDecayConfig
## The run-down look (decay.gd): the palette grade every piece, floor and wall is drawn through, and
## the grime over a piece. A `class_name` holder of `static var`s, read as
## `ObjectArtDecayConfig.<name>`; there is no instance and no autoload.

## The palette grade ObjectArt applies to every piece's, floor's and wall's colour: the hue pulled
## `grade_hue_pull` of the way to `grade_hue` (rust / dun; a colour no more saturated than
## `grade_grey_saturation` takes `grade_grey_hue`), then saturation × `grade_saturation.x` + `.y`
## and value × `grade_value.x` + `.y`, so everything goes dun, rusty or nicotine.
static var grade_hue: float = 0.08
static var grade_hue_pull: float = 0.5
static var grade_grey_hue: float = 0.09
static var grade_grey_saturation: float = 0.08
static var grade_saturation: Vector2 = Vector2(0.55, 0.12)
static var grade_value: Vector2 = Vector2(0.55, 0.04)
## Grime over a piece: one blotch per this many art px² (at least two), this much darker at its
## middle.
static var grime_area: float = 260.0
static var grime_amount: float = 0.24
