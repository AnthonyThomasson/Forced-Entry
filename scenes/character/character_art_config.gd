class_name CharacterArtConfig
## How the body is drawn (scenes/character/): head and shoulder proportions and the limbs' drawn
## widths, which the 3D body mesh reads. A
## `class_name` holder of `static var`s, read as `CharacterArtConfig.<name>`; there is no instance
## and no autoload.

## Head radius as a fraction of the body's width.
static var head_size: float = 0.19
## Shoulder span depth (front to back) as a fraction of the body's width.
static var shoulder_depth: float = 0.54
## Drawn thickness of the body's limbs (body radii), at each joint down the chain: the neck;
## the arm at the shoulder, elbow and wrist; the leg at the hip, knee, calf and ankle; the shoe at
## the heel and toe. Neighbouring segments share a joint's width, so limbs taper smoothly.
static var body_neck_width: float = 0.42
static var body_arm_widths: Array = [0.48, 0.36, 0.3]
static var body_leg_widths: Array = [0.66, 0.46, 0.52, 0.32]
static var body_shoe_widths: Array = [0.38, 0.34]
