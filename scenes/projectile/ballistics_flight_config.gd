class_name BallisticsFlightConfig
## A bullet's flight and what it flies over, for the Projectile System
## (scenes/projectile/projectile.gd): the muzzle and spent speeds, the height it flies at and the
## fly-over, and a collider with no surface.
##
## A `class_name` holder of `static var`s, read as `BallisticsFlightConfig.<name>`; there is no
## instance and no autoload. Going through a collider is `BallisticsPenetrationConfig`, bouncing
## off it `BallisticsRicochetConfig`; the force a hit imparts and the dent it leaves belong to the
## Physics System (`PhysicsImpactConfig`, `PhysicsDeformConfig`).
##
## A bullet is a multi-hit traveler: on each collider it either flies over (no effect, its one
## height is above the collider), ricochets, or penetrates (dealing damage, bleeding speed), and it
## frees itself once its speed drops below `projectile_min_speed` or it exceeds its own
## `max_distance`. Coverage/penetration come from the struck object's surface (see Objects'
## `get_surface()`, 0–100); a collider without a surface uses the `wall_*` fallbacks.

## Default projectile muzzle (top) speed in px/s. Copied onto each bullet's own
## `speed` at spawn (the projectile can still be overridden per-instance there).
static var projectile_speed: float = 3200.0
## Below this speed (px/s) a bullet is spent and frees itself. Head-on hits on hard
## material collapse speed past this in a hit or two, so walls naturally stop bullets.
static var projectile_min_speed: float = 800.0
## Coverage/penetration used for a collider that exposes no `get_surface()`: full cover (never flown
## over) and high penetration.
static var wall_coverage: float = 100.0
static var wall_penetration: float = 100.0
## Coverage is a height on a 0–100 scale. Each bullet flies at one height for its whole flight and
## flies over every collider shorter than it, striking the taller ones. Drawn uniformly from 0–100
## at spawn, a bullet clears a collider of coverage C with chance (100 − C)/100: coverage 30 is
## cleared ~70% of the time and coverage 90 ~10%; coverage 100 is never flown over. The same height
## serves every collider along the flight: behind cover of 50, a body of 60 is struck only by the
## shots between 50 and 60 (or those that punch through the cover), while a crouched body of 35 is
## never reached by a shot that cleared the cover. Negative = random (the game); 0–100 pins every
## bullet to that height, which tests use to pick an outcome.
static var bullet_height: float = -1.0
## Scales the fly-over: the height a bullet needs to clear a collider is 100 − (100 − coverage) ×
## this. At 1.0 it is the coverage itself; at 0 nothing is flown over (every shot meets what it
## reaches); above 1 more is.
static var cover_flyover_scale: float = 1.0
