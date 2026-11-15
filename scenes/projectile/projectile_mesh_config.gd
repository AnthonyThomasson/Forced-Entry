class_name ProjectileMeshConfig
## Projectile domain, the 3D look of the shots (`projectile/art/`; #193 phase 2): the tracer streak
## of a bullet in flight and the spent casing on the floor. A `class_name` holder of `static var`s,
## read as `ProjectileMeshConfig.<name>` (ADR 0003). Lengths and heights are 2D px, as the
## meshes are built in them; how many of each the batches hold is fixed when the layer is
## installed.

## The tracer: a streak this long (px) and this thick, behind the bullet's tip, lit whatever the
## light (`tracer_color` at `tracer_glow`); it shortens to nothing over the last `tracer_fade` px
## of the bullet's range, and the batch shows at most `tracer_capacity` at once.
static var tracer_length: float = 18.0
static var tracer_width: float = 2.0
static var tracer_color: Color = Color(1.0, 0.9, 0.4)
static var tracer_glow: float = 1.0
static var tracer_fade: float = 120.0
static var tracer_capacity: int = 384
## A bullet's height is on the 0..100 cover scale (a wall's 100 is `MirrorConfig.wall_height`, 96
## px): the tracer flies at that times this, and never lower than `tracer_floor` px.
static var height_scale: float = 0.96
static var tracer_floor: float = 2.0
## A spent casing: this long and across (px, as the 2D art), this tall, in brass; it arcs up to
## `casing_arc` px off the floor on its toss. The batch holds `casing_capacity` casings, at least
## what the `Despawner` keeps in the 2D world, so none is left out.
static var casing_size: Vector2 = Vector2(4.5, 2.0)
static var casing_height: float = 1.6
static var casing_color: Color = Color(0.85, 0.7, 0.3)
static var casing_capacity: int = 1024
static var casing_arc: float = 6.0
