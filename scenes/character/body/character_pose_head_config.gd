class_name CharacterPoseHeadConfig
## The head's own life (scenes/character/body/character_pose.gd): the walk's bob, the lean into the
## movement and its spring, the breath and the idle glance. A `class_name` holder of `static var`s,
## read as `CharacterPoseHeadConfig.<name>`; there is no instance and no autoload.

## Head bob along the walk at full speed (px), twice per stride.
static var bob: float = 0.4
## Head lean into the movement at full speed (px), on a soft spring so it settles on a stop.
static var lean: float = 1.2
## Lean spring speed (rad/s).
static var lean_freq: float = 7.0
## Lean spring damping.
static var lean_damping: float = 0.65
## Breathing: the head's slow drift fore and aft (px).
static var breath: float = 0.35
## Breath period (s).
static var breath_period: float = 3.8
## Idle glance: how far the head wanders off the aim while standing (rad), faded out when walking.
static var glance: float = 0.1
