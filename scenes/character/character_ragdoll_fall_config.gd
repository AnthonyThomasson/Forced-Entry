class_name CharacterRagdollFallConfig
## The fall's launch on death (scenes/character/): the topple along the killing blow, the knees'
## buckle, the jitter, a blast's lift and the held item's toss. A `class_name` holder of `static
## var`s, read as `CharacterRagdollFallConfig.<name>`; there is no instance and no autoload.

## The fall's launch: the upper body's push along the killing blow (px/s at the shoulders, fading
## to none at the hips), the knees' forward buckle (px/s) and a random jolt on every point (px/s).
static var hit_topple: float = 60.0
static var knee_buckle: float = 70.0
static var jitter: float = 15.0
## How much of an explosion's shove on a fallen body goes up (a hop off the floor), as a share of
## its speed along it.
static var blast_lift: float = 0.35
## Speed (px/s) a held item is tossed off at as the hand lets go, on top of the body's momentum.
static var drop_toss: float = 70.0
