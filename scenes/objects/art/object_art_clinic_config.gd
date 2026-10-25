class_name ObjectArtClinicConfig
## The ripperdoc's room (scenes/objects/art/): the recliners' vinyl, frames and lamp and the
## clinic's steel, joints, eyes, chips, pins and jars. A `class_name` holder of `static var`s, read
## as `ObjectArtClinicConfig.<name>`; there is no instance and no autoload. A piece's catalogue
## `art_opts` overrides a painter knob for that piece only, keyed by the knob's name without its
## painter prefix (`table_inset` → `inset`).

## The recliners (recliner_painter.gd): the surgical chair's pale vinyl padding, the frames and
## armrests, the surgeon's lamp (glowing).
static var recliner_vinyl_color: Color = Color(0.64, 0.6, 0.48)
static var recliner_frame_color: Color = Color(0.5, 0.47, 0.4)
static var recliner_lamp_color: Color = Color(0.92, 0.84, 0.58)
## The ripperdoc's steel (clinic_painter.gd): the cart's tray, the instruments and arms, the shelf's
## cyberware.
static var clinic_tray_color: Color = Color(0.56, 0.53, 0.44)
static var clinic_chrome_color: Color = Color(0.62, 0.58, 0.48)
static var clinic_joint_color: Color = Color(0.78, 0.22, 0.14)
static var clinic_eye_color: Color = Color(0.86, 0.84, 0.76)
static var clinic_chip_color: Color = Color(0.1, 0.28, 0.15)
static var clinic_pin_color: Color = Color(0.78, 0.66, 0.3)
static var clinic_jar_color: Color = Color(0.5, 0.66, 0.42)
