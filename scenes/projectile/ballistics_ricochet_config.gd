class_name BallisticsRicochetConfig
## Ricochet, for the Projectile System (scenes/projectile/projectile.gd): the material that can
## bounce, how glancing a hit must be, and the damage and speed a ricochet keeps.
##
## A `class_name` holder of `static var`s, read as `BallisticsRicochetConfig.<name>`; there is no
## instance and no autoload.

## Ricochet: only material with penetration ≥ this can bounce, and only on a glancing
## hit (squareness < `bounce_square_max`). Head-on shots always penetrate instead.
static var penetration_bounce_min: float = 80.0
## Squareness (|dir · normal|, 1 = head-on) below which a hard hit ricochets.
static var bounce_square_max: float = 0.5
## Fraction of the (already squareness-scaled) damage a ricochet still deals.
static var bounce_damage_retention: float = 0.3
## Fraction of speed kept after a ricochet.
static var bounce_speed_retention: float = 0.6
