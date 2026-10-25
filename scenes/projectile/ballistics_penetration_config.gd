class_name BallisticsPenetrationConfig
## Going through, for the Projectile System (scenes/projectile/projectile.gd): the least speed a
## bullet punches through at, the speed it loses and the deflection it takes, the probe for the
## face it leaves by, and the blood a round carries out of flesh.
##
## A `class_name` holder of `static var`s, read as `BallisticsPenetrationConfig.<name>`; there is
## no instance and no autoload.

## Minimum speed (px/s) required to penetrate. A bullet slower than this can no longer
## punch through a solid object: it's blocked — deals the impact and then stops
## (embeds). Fly-over and ricochet are unaffected. Set to the un-doubled muzzle speed,
## so penetration only happens in the upper half of the speed range.
static var min_speed: float = 1600.0
## Penetration speed loss: loss = clamp((penetration/100) × this × (2 − squareness),
## 0, 1); speed ×= (1 − loss). Glancing hits (squareness→0) bleed more than head-on.
static var penetrate_loss_scale: float = 0.9
## Max random deflection on penetration, scaled by penetration/100. Degrees.
static var penetrate_deflect_max_deg: float = 12.0
## Exit point: after a bullet penetrates an object, how far past the entry (px) to look for the face
## it leaves by (a probe ray cast back toward the entry). Objects thicker than this report no exit.
static var exit_probe_distance: float = 80.0
## Blood carry: a bullet that passes through a surface with this material (a character's flesh)
## carries its blood; the first non-flesh surface it then hits within `blood_carry_distance` (px,
## measured from where it left the body) is marked with blood.
static var blood_material: StringName = &"flesh"
## Most px a bullet carries blood after leaving a body; the mark fades linearly to nothing at this
## distance.
static var blood_carry_distance: float = 160.0
