class_name CharacterMeshConfig
## Character domain, the 3D body mesh (`body/art/body_mesh.gd`; #193 phase 2,
## `domain-art/meshes.md`): how tall the body stands and how its parts are proportioned. A
## `class_name` holder of `static var`s, read as `CharacterMeshConfig.<name>` (ADR 0003). Lengths
## are 2D pixels, the art's units (the mesh kit converts them to 3D units in one place), or body
## radii where said so. A crouch's height is not here: it comes from the rig, which reads
## `CharacterPostureConfig`.

## How tall a standing body is (px, crown over the floor): three quarters of a wall
## (`MirrorConfig.wall_height`, 96), under a door (`MirrorConfig.door_height`). The rig's own
## heights (a body radius is 14 px and the head sits 100 px up) are the drawing's; the mesh squeezes
## them to this, upright and human in proportion, the horizontal reach the 2D body's.
static var height: float = 74.0
## The head's size over the 2D art's head (`CharacterArtConfig.head_size`): the drawing's own.
static var head_scale: float = 1.0
## The trunk's half width and the vest's over it (body radii), and the trunk's half depth as a share
## of `CharacterArtConfig.shoulder_depth` (the shoulders' depth in body widths).
static var torso_width: float = 0.62
static var vest_grow: float = 1.12
static var torso_depth: float = 0.85
## The trunk reaches this far above the chest joint (body radii), so the head sits on it, and the
## vest covers the trunk from this share of its length up.
static var torso_overshoot: float = 0.12
static var vest_from: float = 0.15
## A plate: its width and height (body radii) and its thickness (px), on the vest's front and back.
static var plate_size: Vector2 = Vector2(0.8, 0.7)
static var plate_thickness: float = 2.0
## A pack on the back: its depth (px), its width (share of the trunk's) and its height (share of the
## trunk's length).
static var pack_depth: float = 5.0
static var pack_width: float = 0.85
static var pack_height: float = 0.7
## How much thicker than the 2D art's drawn widths (`CharacterArtConfig.body_arm_widths`, ...) a
## limb is (near 1: the drawing's own), and how tall a shoe is (body radii).
static var limb_scale: float = 1.1
static var foot_height: float = 0.3
## A fallen body's limbs rest on the floor by their own thickness: a joint below this height (px of
## the 2D drawing) is not squeezed to the standing height, so the body lies on the floor and does
## not sink into it. Standing joints are above it (the squeeze is the same either side).
static var lying_clear: float = 8.0
