class_name ObjectMeshDecorConfig
## Objects domain, the 3D meshes of the rug, the plant, the lamp, the coat rack and the fixtures
## (`object_meshes.gd`; `domain-art/meshes.md`): how tall a piece stands and how its parts are
## proportioned. A `class_name` holder of `static var`s, read as `ObjectMeshDecorConfig.<name>` (ADR
## 0003). Lengths are 2D pixels, the art's units: the mesh kit converts them to 3D units in one
## place, so nothing here is multiplied by `RenderConfig.unit`. A piece's own `art_opts.height`
## overrides a rule of its size.

## A rug: how thick it is and how far its field and medallion lift off its border.
static var rug_height: float = 0.6
static var rug_field_lift: float = 0.3
## A plant: its pot's height, how high its leaves rise and how wide a leaf is.
static var plant_pot_height: float = 14.0
static var plant_height: float = 40.0
static var plant_leaf: float = 3.0
## A floor lamp: how tall it stands to the top of its shade, the shade's height and the pole's
## radius.
static var lamp_height: float = 62.0
static var lamp_shade: float = 10.0
static var lamp_pole: float = 1.0
## A coat rack: how tall its post is and how long a coat hangs.
static var coat_rack_height: float = 72.0
static var coat_rack_coat: float = 22.0
## A wall fixture: how thick it is, where a mirror's frame starts and how tall it is, and the height
## of a towel bar.
static var fixture_thickness: float = 3.0
static var fixture_mirror_base: float = 46.0
static var fixture_mirror_height: float = 34.0
static var fixture_bar_height: float = 44.0
