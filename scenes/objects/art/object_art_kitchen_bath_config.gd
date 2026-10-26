class_name ObjectArtKitchenBathConfig
## Kitchen and bathroom pieces (scenes/objects/art/): the counter (backsplash, tap), the appliances
## (panel, metal, glass, CRT), the bath, toilet and shower, and the kitchenette's hotplate. A
## `class_name` holder of `static var`s, read as `ObjectArtKitchenBathConfig.<name>`; there is no
## instance and no autoload. A piece's catalogue `art_opts` overrides a painter knob for that piece
## only, keyed by the knob's name without its painter prefix (`table_inset` → `inset`).

## A backsplash band along the back edge by default, and the tap's metal (the bath's taps too).
static var counter_backsplash: bool = true
static var counter_tap_color: Color = Color(0.52, 0.46, 0.36)
## The front panel by default ("plain", "burners", "fridge", "microwave", "washer", "dryer" or
## "tv"), its metal parts, and the glass of a microwave or washer door.
static var appliance_panel: String = "plain"
static var appliance_metal_color: Color = Color(0.46, 0.4, 0.32)
static var appliance_glass_color: Color = Color(0.14, 0.15, 0.12)
## A TV's boxy CRT case (grimy grey plastic).
static var appliance_crt_color: Color = Color(0.32, 0.29, 0.24)
## Water in a bath and a toilet bowl.
static var bath_water_color: Color = Color(0.42, 0.44, 0.3)
## Shower tray tile size (art px).
static var bath_tile_px: int = 8
## The shower screen's glass.
static var bath_shower_glass_color: Color = Color(0.5, 0.52, 0.44)
## The kitchenette's hotplate (hotplate_painter.gd): its crate, the hot ring (glowing) and the pan.
static var hotplate_crate_color: Color = Color(0.36, 0.26, 0.16)
static var hotplate_ring_color: Color = Color(1.0, 0.42, 0.12)
static var hotplate_pan_color: Color = Color(0.2, 0.19, 0.18)
