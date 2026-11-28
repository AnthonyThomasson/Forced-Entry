class_name ObjectMeshItemConfig
## Objects domain, the 3D meshes of the small items (`item_mesh.gd`; `domain-objects/heights.md`,
## `docs/stacked-items.md`): how tall each kind stands. A `class_name` holder of `static var`s, read
## as `ObjectMeshItemConfig.<name>` (ADR 0003). Lengths are 2D pixels (42.3 px a metre). A plate, a
## cup, a bowl and a book lie within a step (`DoorFallConfig.step_over`, 10 px): a walker steps over
## one on the floor; a lamp, a monitor, a box and a crate are taller, an obstacle. A piece's own
## `art_opts.height` overrides its kind's.

## Tableware: a plate (a dinner plate is 2 cm), a cup, a bowl.
static var plate_height: float = 1.5
static var cup_height: float = 5.0
static var bowl_height: float = 4.0
## A paperback.
static var book_height: float = 2.5
## A desk lamp (its head), a monitor (screen and stand).
static var desk_lamp_height: float = 14.0
static var monitor_height: float = 14.0
## A cardboard box and a wooden crate.
static var box_height: float = 12.0
static var crate_height: float = 16.0
