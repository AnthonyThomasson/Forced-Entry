class_name CharacterRagdollConfig
## The ragdoll's build (scenes/character/body/character_ragdoll.gd): the belly points, the collision
## radii and the point masses. A `class_name` holder of `static var`s, read as
## `CharacterRagdollConfig.<name>`; there is no instance and no autoload.

## Belly and back points off the spine (keep the trunk rigid).
static var belly: float = 0.4
## Collision radii: the trunk's is half its depth, so it lies on its back or front with thickness.
static var torso_radius: float = 0.5
static var head_radius: float = 0.38
static var limb_radius: float = 0.24
## Point masses (relative): a heavy trunk (seven points), lighter limbs toward their ends.
static var torso_mass: float = 1.0
static var head_mass: float = 0.8
static var elbow_mass: float = 0.25
static var hand_mass: float = 0.15
static var knee_mass: float = 0.6
static var ankle_mass: float = 0.35
