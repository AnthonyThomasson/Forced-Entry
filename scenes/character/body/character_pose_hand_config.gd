class_name CharacterPoseHandConfig
## How the hands and the weapon trail the aim (scenes/character/body/character_pose.gd): the steady
## (aim) hands', the weapon's and the free hands' springs, their pace spread and the aim drift. A
## `class_name` holder of `static var`s, read as `CharacterPoseHandConfig.<name>`; there is no
## instance and no autoload.

## Steady hands (aiming, supporting): follow the aim closely.
static var aim_freq: float = 11.0
## Steady hands: settle without wobble.
static var aim_damping: float = 0.95
## Steady hands: furthest behind the aim.
static var aim_max_lag: float = 0.6
## Weapon: heavier than the hand holding it.
static var weapon_freq: float = 7.0
## Weapon: swings a hair past and settles.
static var weapon_damping: float = 0.8
## Weapon: furthest behind the aim.
static var weapon_max_lag: float = 0.7
## Free hands: follow the aim loosely.
static var hand_freq: float = 8.0
## Free hands: a little give.
static var hand_damping: float = 0.85
## Free hands: furthest behind the aim.
static var hand_max_lag: float = 0.9
## How far apart the two free hands' paces are (fraction of `hand_freq`; left slower).
static var hand_pace_spread: float = 0.3
## A steady hand's sideways drift at full walking speed (px).
static var aim_drift: float = 0.5
