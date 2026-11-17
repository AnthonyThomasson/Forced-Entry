class_name LightingCostConfig
## What the Lighting domain's 3D lights cost (`docs/lighting.md`): how many cast a
## shadow, how many are on, and how often that is chosen again. A `class_name` holder of
## `static var`s, read as `LightingCostConfig.<name>` (ADR 0003).

## The positional shadow atlas of the 3D view (texels on a side): six depth faces of a light each.
static var shadow_atlas: int = 4096
## The cost: at most `shadow_lights` lights, the nearest to the view's focus, cast a shadow (each is
## six depth passes); at most `max_lights` of the world's lights are on at once, the nearest to the
## focus that reach the view (ranked by the distance less the pool's radius); the choice is made
## again every `refresh` s, or once the focus moved `refocus` px or the zoom changed, and a light
## keeps its shadow unless a rival is `keep_margin` times nearer. Counted in the district (the
## street and bedroom shots): 95 and 98 lights reach the view at zoom 0.5, 30 and 35 at zoom 1, 6
## and 19 at 2, so 48 keeps every one at zoom 1 and the nearest pools at 0.5.
static var shadow_lights: int = 6
static var max_lights: int = 48
static var refresh: float = 0.3
static var refocus: float = 48.0
static var keep_margin: float = 0.75
## How long (s) a light takes to fade in or out when the cap switches it, so a view that moves does
## not pop a pool on or off.
static var fade_time: float = 0.2
