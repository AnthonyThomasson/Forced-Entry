class_name ObjectArtDoorConfig
## A door's drawing (door_painter.gd): the metal, the glass and the fittings, in the run-down look.
## A `class_name` holder of `static var`s, read as `ObjectArtDoorConfig.<name>`; there is no
## instance and no autoload.

## The hinge pins, the handle, the rivets and the lock plate.
static var fitting_color: Color = Color(0.46, 0.43, 0.38)
static var handle_color: Color = Color(0.74, 0.66, 0.42)
## The panes: tint, and the pale streak of glare across them.
static var glass_color: Color = Color(0.5, 0.62, 0.64, 0.55)
static var glass_glare: Color = Color(0.84, 0.92, 0.9, 0.7)
## A panel's recess, as a share darker than the leaf.
static var panel_darken: float = 0.22
## Pixels between two planks' seams, between two rivets and the pane grid's cell.
static var plank_px: int = 8
static var rivet_px: int = 6
static var pane_px: int = 12
## Scratches a wooden leaf takes, rust patches a steel one.
static var wood_scratches: int = 4
static var steel_rust: int = 3
