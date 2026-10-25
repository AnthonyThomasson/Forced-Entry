class_name PhysicsConfig
## The Physics System's master switches and shared mask (scenes/physics/): the wall mask, debris
## and hit particles (switch, scale, cap).
##
## A `class_name` holder of `static var`s — read as `PhysicsConfig.<name>`; there is no
## instance and no autoload. A hit's shove is `PhysicsImpactConfig`, deformation
## `PhysicsDeformConfig` and `PhysicsDeformLookConfig`, the ragdoll solver `PhysicsRagdollConfig`
## and a grenade burst's look `PhysicsExplosionConfig`; blood is its own sub-domain's
## (`BloodConfig`). Ballistics (fly-over/ricochet/penetration) live in the Ballistics holders
## (`BallisticsFlightConfig` ...); the character's walking-push knobs in CharacterPushConfig.

## Physics layer mask walls and furniture live on: the ragdoll's wall sweep and the blood pools' and
## flows' collision queries all test against it.
static var wall_mask: int = PhysicsLayers.SOLID
## Master switch for debris: off = hits spray no chips (Physics.spawn_debris spawns nothing).
static var debris_enabled: bool = true
## Master switch for hit particles: off = hits emit no entry/exit particle bursts (HitParticles
## spawns nothing).
static var hit_particles_enabled: bool = true
## Scales every burst's particle count (1 = the style tables as written); 0 emits nothing.
static var hit_particles_scale: float = 1.0
## Most particles one burst may hold, however hard the hit.
static var hit_particles_max: int = 24
