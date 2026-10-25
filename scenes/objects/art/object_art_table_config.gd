class_name ObjectArtTableConfig
## Tables and chairs (scenes/objects/art/): the table top's planks, rim, corners, inset and runner;
## the chair's back and slats; the office chair's base. A `class_name` holder of `static var`s, read
## as `ObjectArtTableConfig.<name>`; there is no instance and no autoload. A piece's catalogue
## `art_opts` overrides a painter knob for that piece only, keyed by the knob's name without its
## painter prefix (`table_inset` → `inset`).

## Plank width (art px); planks run along the table's long side.
static var table_plank_px: int = 9
## Bevelled rim width (art px) inside the outline.
static var table_rim_px: int = 2
## Corner rounding of the top (art px).
static var table_corner_radius: int = 3
## A recessed centre panel (`table_inset`), inset `table_inset_margin` art px from the edge.
static var table_inset: bool = false
static var table_inset_margin: int = 7
## A cloth runner down the long axis: its width as a fraction of the short side, and its color.
static var table_runner: bool = false
static var table_runner_width: float = 0.26
static var table_runner_color: Color = Color(0.5, 0.42, 0.3)
## Depth of the back (rail + slat gap) as a fraction of the chair's depth.
static var chair_back_depth: float = 0.26
## Spindles between the back rail and the seat.
static var chair_slats: int = 3
## The star base's metal.
static var office_chair_base_color: Color = Color(0.24, 0.2, 0.16)
