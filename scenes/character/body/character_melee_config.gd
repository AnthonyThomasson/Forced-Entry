class_name CharacterMeleeConfig
## The punch and the kick (scenes/character/body/): their impulse and damage, the kick's reach,
## timing and foot height, and the body's twist and lunge into a punch. A `class_name` holder of
## `static var`s, read as `CharacterMeleeConfig.<name>`; there is no instance and no autoload.

## Base central impulse a full-extension punch imparts to a pushable object, scaled by the
## swing's range of motion (0 point-blank .. 1 full reach). A shoved RigidBody slides
## ≈ impulse / (mass × PhysicsImpactConfig.body_linear_damp) before settling.
static var punch_impulse: float = 900.0
## Base damage a full-extension punch reports, scaled by the same range of motion. Surfaced
## through hit_landed for the HUD; a punch does not deform what it hits.
static var punch_damage: float = 8.0
## Central impulse a kick imparts to a pushable object, and the damage it reports (both at full
## strength: a kick lands only while the foot is being thrown out).
static var kick_impulse: float = 2200.0
static var kick_damage: float = 14.0
## How far (px) from the body centre the foot is thrown along the facing, and the radius of the
## circle that strikes.
static var kick_reach: float = 44.0
static var kick_radius: float = 6.0
## Seconds the foot takes to be thrown out (the strike) and to be drawn back (no other kick starts
## meanwhile).
static var kick_strike_time: float = 0.09
static var kick_recover_time: float = 0.22
## How high (body radii) the thrown foot is held off the floor: it must stay within the leg's length
## of the hip.
static var kick_foot_height: float = 2.1
## A punch's body: the shoulders twist toward the punching side by this much (rad) and the upper
## body lunges this far ahead (px) at full extension.
static var pose_punch_twist: float = 0.5
static var pose_punch_lunge: float = 4.0
