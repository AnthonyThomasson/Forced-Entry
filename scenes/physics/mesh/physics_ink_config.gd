class_name PhysicsInkConfig
## Physics domain, the 3D look of what lies flat on the floor (#193 phase 2; `ink_fx.gd`,
## `pool_ink.gd`, `domain-physics/meshes.md`): blood (splats, a bleed-out pool, prints, smears)
## and the scorch of a blast. A `class_name` holder of `static var`s, read as
## `PhysicsInkConfig.<name>` (ADR 0003). Lengths and heights are 2D px. Colours, shapes, sizes,
## caps and drying times are the 2D ones' own (`BloodConfig`, `BloodSplatConfig`,
## `BloodPoolConfig`, `PhysicsExplosionConfig`): read again, not copied; this holds what only the
## 3D has. A mark lies as a flat mesh over the ground, each kind on a layer of its own (the shared
## decal rule, `MeshNodes.decal`: a layer floats `MeshKitConfig.decal_layer_step` px higher than the
## last, so none shares a depth), in the order the 2D layers draw them in (a pool, then a splat over
## it, then prints and smears, the scorch over all), over the floor's own wear (its top is the
## stencil's tier 4 and a fraction, under layer 5; a rug's top is under one layer) and under what
## lies on it.

## The decal layer each kind of mark lies on, in the order they are drawn: a pool, a splat, a print
## or smear, a scorch (a height of `MeshKitConfig.decal_lift` + layer * `decal_layer_step` px).
static var pool_layer: float = 5.0
static var splat_layer: float = 5.8
static var print_layer: float = 6.6
static var scorch_layer: float = 7.4
## A mark that lies over another of its kind (a splat's wet highlight, a scorch's core) lies this
## many layers higher.
static var over_layer: float = 0.4
## Blood dries in this many steps, from `BloodConfig.color` to `dried_color` over the 2D drying
## time: a stepped tone, not a blend. A mark dry writes nothing again.
static var dry_steps: int = 4
## The tone (the floor the 2D alpha shows through) a see-through mark of the 2D is laid over, as
## 3D marks are opaque: a scorch's rim and a faint print take their alpha by it.
static var ground_tone: Color = Color(0.36, 0.36, 0.34)
## A print's or smear's opacity steps: its 2D alpha is rounded up to the nearest of these, each
## laid over `ground_tone` by it.
static var alpha_steps: Array = [0.35, 0.6, 0.85]
## A pool is redrawn at most this often (s) while it grows or soaks; its picture is this many
## times finer than its flow cells (a cell is `BloodPoolConfig.flow_cell_size` px).
static var pool_interval: float = 0.2
static var pool_upscale: int = 2
## A pool's fill (0..1) at which it begins, and above which it takes its deep tone; blood that has
## soaked in (`BloodSurfaceConfig`) takes this much of its tone.
static var pool_threshold: float = 0.3
static var pool_deep: float = 0.6
static var pool_soaked: float = 0.8
