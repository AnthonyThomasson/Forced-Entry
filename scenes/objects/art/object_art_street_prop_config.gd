class_name ObjectArtStreetPropConfig
## The sidewalk clutter of a district (street_prop_painter.gd), in the grimy steel family: the
## vending machine, the street bench, the bin, the drain grate and the litter. The steel itself is
## the catalogue colour; these are the rest. A `class_name` holder of `static var`s, read as
## `ObjectArtStreetPropConfig.<name>`; there is no instance and no autoload. A piece's catalogue
## `art_opts` overrides a painter knob for that piece only, keyed by the knob's name without its
## painter prefix (`prop_top_color` -> `top_color`).

## The lighter steel of a machine's face and a bin's lid, the rust-orange trim, the dull glass of
## the vending window (glowing) and the bench's slats.
static var prop_top_color: Color = Color(0.58, 0.58, 0.55)
static var prop_accent_color: Color = Color(0.62, 0.34, 0.17)
static var prop_glass_color: Color = Color(0.3, 0.4, 0.42)
static var prop_wood_color: Color = Color(0.5, 0.38, 0.24)
## The drinks in the vending window, and the litter's scraps.
static var prop_products: Array[Color] = [
	Color(0.9, 0.3, 0.2), Color(0.95, 0.8, 0.2), Color(0.3, 0.7, 0.9), Color(0.5, 0.85, 0.4),
]
static var prop_scraps: int = 9
## The bench's slats, and how many bars a drain grate has per this many px.
static var prop_slats: int = 4
static var prop_grate_step: int = 4
