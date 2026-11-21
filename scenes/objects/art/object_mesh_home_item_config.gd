class_name ObjectMeshHomeItemConfig
## Objects domain, the 3D meshes of the home's small items (`item_home_mesh.gd`,
## `docs/stacked-items.md` SI13): how tall each stands. A `class_name` holder of `static var`s, read
## as `ObjectMeshHomeItemConfig.<name>` (ADR 0003). Lengths are 2D pixels (42.3 px a metre). A
## keyboard, papers, a board, a tool roll, a clock, a fruit bowl, a vise and a vase lie within a
## step (`DoorFallConfig.step_over`, 10 px; the rule is "no higher than", so the vase's 10, the
## highest, is at the line and inside it): a walker steps over one on the floor. A piece's own
## `art_opts.height` overrides its kind's.

## A keyboard.
static var keyboard_height: float = 1.5
## A few sheets of paper.
static var papers_height: float = 0.6
static var clock_height: float = 4.0
static var vase_height: float = 10.0
## A bowl with its fruit heaped over the rim.
static var fruit_bowl_height: float = 6.0
static var cutting_board_height: float = 1.5
## A hammer, a wrench and a screwdriver laid together.
static var tools_height: float = 2.5
static var vise_height: float = 5.0
