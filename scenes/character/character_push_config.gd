class_name CharacterPushConfig
## Walking into pieces and being shoved (scenes/character/): the walking push and its slow-down and
## carry cap, the body's mass and knockback friction, and the legs pressing pieces. Walking the body
## into a pushable object (anything exposing `apply_impulse`: furniture, not walls) shoves it
## through the same impulse pipeline a projectile uses, divided by the object's mass; pushing also
## slows the character (heavier = slower), and a fast object sliding into the character shoves it
## back. A `class_name` holder of `static var`s, read as `CharacterPushConfig.<name>`; there is no
## instance and no autoload.

## Base impulse per second of contact the character imparts to an object, scaled by how
## hard the character is moving into it (input strength 0–1). Frame-rate independent.
static var impulse: float = 54_000.0
## How much each unit of the pushed object's `mass` reduces the character's speed while
## pushing (speed_mult = 1 − heaviest_mass × this, floored by `slow_min`).
static var slow_per_weight: float = 0.02
## Floor on the character's speed multiplier while pushing.
static var slow_min: float = 0.15
## Fraction of the character's walk speed an object it pushes may be driven up to (1 = it is
## carried at walking pace, never launched ahead of the character).
static var carry_factor: float = 1.0
## How fast (multiplier units per second) the push slow-down eases back to full speed once
## contact is lost, so a one-frame gap doesn't snap the character's speed.
static var slow_release: float = 3.0
## The character's mass for *incoming* knockback: an object sliding into the character
## shoves them by impulse / this. Higher = the character shrugs off hits unless struck hard.
static var player_mass: float = 40.0
## Deceleration (px/s²) that bleeds the character's knockback velocity back to zero.
static var knockback_friction: float = 1600.0
## Radius (px) of the circle a foot and a knee sweep with, and the shove (impulse per second of
## contact, divided by the piece's mass, like a walking body's `impulse`) a leg pressing a
## pushable piece gives it.
static var leg_radius: float = 3.5
static var leg_push_impulse: float = 30_000.0
