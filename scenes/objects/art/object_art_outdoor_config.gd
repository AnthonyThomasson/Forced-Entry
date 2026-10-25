class_name ObjectArtOutdoorConfig
## The pieces outside (scenes/objects/art/): the parked beater car and the street lamp (head, plate,
## flyer, lens, sign). A `class_name` holder of `static var`s, read as
## `ObjectArtOutdoorConfig.<name>`; there is no instance and no autoload. A piece's catalogue
## `art_opts` overrides a painter knob for that piece only, keyed by the knob's name without its
## painter prefix (`table_inset` → `inset`).

## The parked car's tyres, windows and lamps.
static var car_tyre_color: Color = Color(0.1, 0.09, 0.08)
static var car_glass_color: Color = Color(0.24, 0.26, 0.24)
static var car_light_color: Color = Color(0.85, 0.75, 0.5)
## The parked car is a beater: its paint taken this far (0..1) to `car_beater_color` (rust-brown),
## patched with primer.
static var car_beater: float = 1.0
static var car_beater_color: Color = Color(0.42, 0.3, 0.2)
## The overhead head a streetlight draws by default (`cobra` lamp or `sign`), how long the head is
## along the arm (art px), the base plate, the arm and head housing, the flyer taped round the post,
## the lens (glowing: sodium) and a sign's board.
static var streetlight_head: String = "cobra"
static var streetlight_head_px: int = 15
static var streetlight_plate_color: Color = Color(0.2, 0.18, 0.15)
static var streetlight_head_color: Color = Color(0.3, 0.29, 0.25)
static var streetlight_flyer_color: Color = Color(0.82, 0.78, 0.62)
static var streetlight_lens_color: Color = Color(1.0, 0.74, 0.4)
static var streetlight_sign_color: Color = Color(0.07, 0.07, 0.08)
