class_name ObjectMeshStateConfig
## Objects domain, the state a furniture mesh shows (`furniture_rig.gd`; `domain-art/meshes.md`): a
## `class_name` holder of `static var`s, read as `ObjectMeshStateConfig.<name>` (ADR 0003).

## How strongly a lit glow part glows (a lamp's bulb, a screen, the hot ring).
static var glow_strength: float = 1.0
## A bed's blanket while someone lies on it: its height scale (1 is raised), how close (px) to the
## bed's centre a character in an interaction counts as lying on it, and how many frames pass
## between two looks.
static var occupied_blanket_scale: float = 0.25
static var occupied_radius: float = 3.0
static var occupied_every: int = 6
