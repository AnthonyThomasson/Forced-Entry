class_name ObjectArtTechConfig
## Electronics and security hardware (scenes/objects/art/): the den's rigs (dark parts, ledges,
## LEDs) and the vestibule's barricade, sandbags, beams and numbers. A `class_name` holder of
## `static var`s, read as `ObjectArtTechConfig.<name>`; there is no instance and no autoload. A
## piece's catalogue `art_opts` overrides a painter knob for that piece only, keyed by the knob's
## name without its painter prefix (`table_inset` → `inset`).

## The den's hardware (tech_painter.gd): dark parts (rails, frames, cables), the keyboard ledge, and
## the LEDs a rack and the rig's halo show besides their screen colour.
static var tech_dark_color: Color = Color(0.14, 0.12, 0.09)
static var tech_ledge_color: Color = Color(0.36, 0.26, 0.16)
static var tech_led_colors: Array[Color] = [Color(0.85, 0.22, 0.14), Color(0.3, 0.95, 0.4)]
## The vestibule's steel (security_painter.gd): the barricade's hazard stripe and sandbags, the
## scanner's beam (glowing), the lockers' numbers.
static var security_hazard_color: Color = Color(0.88, 0.68, 0.16)
static var security_sandbag_color: Color = Color(0.55, 0.47, 0.32)
static var security_beam_color: Color = Color(1.0, 0.22, 0.18)
static var security_number_color: Color = Color(0.86, 0.84, 0.76)
