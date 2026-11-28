class_name BallisticsFlightConfig
## A bullet's flight, for the Projectile System (scenes/projectile/projectile.gd): the muzzle and
## spent speeds, the up-and-down scatter of a shot, and a body with no surface.
##
## A `class_name` holder of `static var`s, read as `BallisticsFlightConfig.<name>`; there is no
## instance and no autoload. Going through a collider is `BallisticsPenetrationConfig`, bouncing
## off it `BallisticsRicochetConfig`; the force a hit imparts and the dent it leaves belong to the
## Physics System (`PhysicsImpactConfig`, `PhysicsDeformConfig`).
##
## A bullet is a 3D ray that meets what its line crosses (cover is hit or cleared by its real
## height: `docs/cover-and-stance.md`): on each body it ricochets or penetrates (dealing damage,
## bleeding speed), and it frees itself once its speed drops below `projectile_min_speed` or it
## exceeds its own `max_distance`. Penetration comes from the struck object's surface (see Objects'
## `get_surface()`, 0–100); a body without a surface uses `wall_penetration`.

## Default projectile muzzle (top) speed in px/s. Copied onto each bullet's own
## `speed` at spawn (the projectile can still be overridden per-instance there).
static var projectile_speed: float = 3200.0
## Below this speed (px/s) a bullet is spent and frees itself. Head-on hits on hard
## material collapse speed past this in a hit or two, so walls naturally stop bullets.
static var projectile_min_speed: float = 800.0
## The penetration of a body that exposes no `get_surface()`: high.
static var wall_penetration: float = 100.0
## How much of a gun's spread (its `spread_deg`) scatters the shot up and down: 1 is the same cone
## in both axes, 0 shoots flat along the aim line (a wider cone misses over and under a body as it
## misses beside it).
static var vertical_spread_scale: float = 1.0
