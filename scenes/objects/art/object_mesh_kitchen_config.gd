class_name ObjectMeshKitchenConfig
## Objects domain, the 3D meshes of the counter, the appliances and the hotplate
## (`object_meshes.gd`; `domain-art/meshes.md`): how tall a piece stands and how its parts are
## proportioned. A `class_name` holder of `static var`s, read as `ObjectMeshKitchenConfig.<name>`
## (ADR 0003). Lengths are 2D pixels, the art's units: the mesh kit converts them to 3D units in one
## place, so nothing here is multiplied by `RenderConfig.unit`. A piece's own `art_opts.height`
## overrides a rule of its size.

## A counter: how tall it stands, its top slab, how far its backsplash rises above the top and how
## deep a single and a deep basin sink below it.
static var counter_height: float = 38.0
static var counter_top: float = 4.0
static var counter_splash: float = 6.0
static var counter_basin: float = 6.0
static var counter_deep_basin: float = 12.0
## An appliance: how tall each panel stands (`ObjectArtKitchenBathConfig.appliance_panel`), a fridge
## of at most `fridge_mini_area` px squared is a mini fridge `fridge_mini_height` tall, and the
## thickness of a door, handle or glass proud of its face.
static var appliance_heights: Dictionary = {
	"plain": 38.0, "burners": 38.0, "fridge": 74.0, "microwave": 22.0, "washer": 36.0,
	"dryer": 36.0, "tv": 26.0,
}
static var fridge_mini_height: float = 40.0
static var fridge_mini_area: float = 2500.0
static var appliance_proud: float = 1.0
## The hotplate: its crate, its plate on top and the pan.
static var hotplate_crate_height: float = 12.0
static var hotplate_plate_height: float = 3.0
static var hotplate_pan_height: float = 4.0
