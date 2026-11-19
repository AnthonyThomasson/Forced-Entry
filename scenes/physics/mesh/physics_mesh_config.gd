class_name PhysicsMeshConfig
## Physics domain, the 3D look of the debris and the hit particles (`mesh/`,
## `domain-physics/meshes.md`): how high a chip flies and lies, how a burst's bits arc, and how
## many the batches hold. A `class_name` holder of `static var`s, read as
## `PhysicsMeshConfig.<name>` (ADR 0003). Lengths and heights are 2D px, as the meshes are built
## in them; how many chips a batch holds is the `Despawner`'s cap, taken when the layer is
## installed. What a chip or a bit is (its colour, size, count, life, speed) is the 2D styles' own
## (`DebrisSpawner.STYLES`, `HitParticles.STYLES`): read again, not copied.

## A hit's height is real (px above the floor, `HitInfo.height`): a burst leaves the surface at that
## times this (1: where it struck).
static var height_scale: float = 1.0
## A chip is this thick (px); it lies with its underside `rest_height` px over the ground (or over
## the piece it lies on), above the blood and the scorch that lie there (`PhysicsInkConfig`), as in
## 2D.
static var chip_thickness: float = 1.0
static var rest_height: float = 2.1
## How many chips may be in the air at once, besides those that lie (the batches hold the
## `Despawner`'s cap of the latter): the 2D chips in the air are the `Despawner`'s too.
static var flying_room: int = 256
## A burst's bits (`HitParticles`): a cube as big as the 2D particle (px), flung up at `bit_lift`
## times their horizontal speed, pulled back by `bit_gravity` (px/s²) and stopped by the floor at
## `rest_height`; they shrink away over the last `bit_shrink` share of their life (the 2D alpha
## fade, with no blending).
static var bit_lift: float = 0.5
static var bit_gravity: float = 520.0
static var bit_shrink: float = 0.45
## The bits and the sparks the batches hold at most: a burst past them shows what fits (the
## oldest burst's bits are not taken back).
static var bit_capacity: int = 768
static var spark_capacity: int = 256
## A spark (the metal style's "spark" tint) is lit whatever the light, this colour, this strongly:
## no real light (phase 3's flashes are lights).
static var spark_color: Color = Color(1.0, 0.82, 0.45)
static var spark_glow: float = 1.0
