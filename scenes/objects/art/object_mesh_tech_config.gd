class_name ObjectMeshTechConfig
## Objects domain, the 3D meshes of the den's hardware, the ripperdoc's steel and the security
## vestibule (`tech_mesh.gd`, `clinic_mesh.gd`, `security_mesh.gd`; `domain-art/meshes.md`): how
## tall a piece stands. A `class_name` holder of `static var`s, read as
## `ObjectMeshTechConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's units: the mesh kit
## converts them to 3D units in one place. A piece's own `art_opts.height` overrides the one rule of
## its kind that has one.

## The netrunner's monitor wall: the desk ledge's top, how far a screen stands over it and how high
## the backboard the screens hang on rises; a server rack's height.
static var desk_height: float = 31.0
static var screen_height: float = 22.0
static var rail_height: float = 62.0
static var rack_height: float = 80.0
## The ripperdoc's tool cart (its top, and the rim round its tray) and the cyberware shelf (its
## height and how many tiers).
static var cart_height: float = 34.0
static var cart_rim: float = 2.0
static var cyber_height: float = 64.0
static var cyber_tiers: int = 3
## The security vestibule: the barricade's slab, the scanner post and a locker.
static var barricade_height: float = 40.0
static var scanner_height: float = 84.0
static var locker_height: float = 77.0
