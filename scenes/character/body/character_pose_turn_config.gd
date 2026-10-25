class_name CharacterPoseTurnConfig
## How the body turns to the aim (scenes/character/body/character_pose.gd): the lag catch, and the
## head's, shoulders' and hips' springs and the hips' twist before the feet re-plant. A `class_name`
## holder of `static var`s, read as `CharacterPoseTurnConfig.<name>`; there is no instance and no
## autoload.

## How fast a part past its `max_lag` is reeled back toward it (1/s): high = tight, low = loose.
static var lag_catch: float = 14.0
## Head: turns to the aim first.
static var head_freq: float = 12.0
## Head: barely overshoots.
static var head_damping: float = 0.9
## Head: furthest behind the aim.
static var head_max_lag: float = 0.8
## Shoulders: follow last.
static var torso_freq: float = 5.5
## Shoulders: ease past and settle.
static var torso_damping: float = 0.75
## Shoulders: furthest behind the aim.
static var torso_max_lag: float = 1.2
## Hips (and feet): turn to the walking direction.
static var hip_freq: float = 9.0
## Hips: barely overshoot.
static var hip_damping: float = 0.9
## How far the shoulders may twist off the planted hips before the feet re-plant toward the aim
## (rad).
static var hip_twist: float = 0.9
