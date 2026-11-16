class_name LightingCostConfig
## What the Lighting domain's 3D lights cost (#193 phase 3, `docs/lighting.md`): how many cast a
## shadow, how many are on, and how often that is chosen again. A `class_name` holder of
## `static var`s, read as `LightingCostConfig.<name>` (ADR 0003).

## The positional shadow atlas of the 3D view (texels on a side): six depth faces of a light each.
static var shadow_atlas: int = 4096
## The cost: at most `shadow_lights` lights, the nearest to the view's focus, cast a shadow (each is
## six depth passes); at most `max_lights` of the world's lights are on at once, the nearest to the
## focus that reach the view; the choice is made again every `refresh` s or once the focus moved
## `refocus` px, and a light keeps its shadow unless a rival is `keep_margin` times nearer.
static var shadow_lights: int = 6
static var max_lights: int = 40
static var refresh: float = 0.3
static var refocus: float = 48.0
static var keep_margin: float = 0.75
