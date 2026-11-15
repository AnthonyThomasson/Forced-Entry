class_name ObjectMeshStateConfig
## Objects domain, the state a furniture mesh shows (`furniture_rig.gd`; `domain-art/meshes.md`): a
## `class_name` holder of `static var`s, read as `ObjectMeshStateConfig.<name>` (ADR 0003).

## How strongly a lit glow part glows by default (the hot ring), and the dimmer bulb and screen.
static var glow_strength: float = 1.0
static var bulb_strength: float = 0.6
static var screen_strength: float = 0.6
## A bed's blanket while someone lies on it: its height scale (1 is raised), and how many frames
## pass between two looks.
static var occupied_blanket_scale: float = 0.25
static var occupied_every: int = 6
