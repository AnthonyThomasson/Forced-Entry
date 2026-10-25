class_name CharacterStunConfig
## Being stunned (a grenade's flash and bang, `Character.take_stun`; `docs/grenades.md` G13): the
## slowed pace, the aim's sway, the drift and the recovery tail, and the stunned look (hunch,
## staggering stride, limp, wander, sway, bob). A `class_name` holder of `static var`s, read as
## `CharacterStunConfig.<name>`; there is no instance and no autoload.

## The most a stunned character moves of its speed (x0.45 at the full level).
static var speed: float = 0.45
## Furthest (degrees) the aim sways off where it points at the full level; applied to where shots
## and throws go.
static var sway: float = 25.0
## The effect tails off over the last this many seconds: the level falls linearly from 1 to 0 over
## them.
static var recover_tail: float = 1.5
## How fast (px/s) a stunned character drifts sideways of the way it walks, at the full level.
static var drift: float = 20.0
## The stunned look (character_pose.gd / character_rig.gd; drawn only: nothing here changes where it
## goes or what it hits). It eases toward the level at `look_ease` (1/s), so it comes on and
## wears off without a jump; a ride's pose wins over it.
static var look_ease: float = 6.0
## The hunch: the spine and the neck pitch forward this far (degrees) at the full level, on top of a
## crouch's own pitch.
static var hunch_pitch: float = 15.0
## The stagger, at the full level: each stride is this share of a steady one (its length and its
## feet's swing), the steps run uneven (a limp: one step this much longer than the next, as a share
## of the stride's pace; and a slow wander of the pace by `stagger_wander`), the hips sway this
## far (px) each way over the planted foot and the head lolls this far (px) each way, both while
## walking.
static var stagger_stride: float = 0.55
static var stagger_limp: float = 0.4
static var stagger_wander: float = 0.3
static var stagger_sway: float = 4.0
static var stagger_bob: float = 3.0
