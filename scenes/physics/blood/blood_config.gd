class_name BloodConfig
## Tuning for the blood system (scenes/physics/blood/): the master switch and what every blood file
## shares, the colours, the draw layers and the batched decal layer's cap and drying. A
## `class_name` holder of `static var`s — read as `BloodConfig.<name>`; there is no instance and no
## autoload.
##
## Blood is its own physical reaction, kept separate from the debris and deformation knobs in
## PhysicsConfig and PhysicsDeformConfig. A wounded body (BloodWound) throws a quick spray of
## splatters when it is hit (`BloodSprayConfig`), then keeps dripping (`BloodDripConfig`), each drop
## landing as a BloodSplat (`BloodSplatConfig`). A dead body also bleeds out one slow, wide pool
## (`BloodPoolConfig`) from where it came to rest, steered and soaked by the floor
## (`BloodSurfaceConfig`). Feet print it (`BloodPrintConfig`) and objects smear it
## (`BloodSmearConfig`, `BloodSmearLookConfig`, `BloodTrailConfig`).

## Master switch for blood: off = hits leave no splatter or drips and dead bodies no bleed-out
## (BloodWound.record / Physics.bleed_out spawn nothing).
static var enabled: bool = true
## Cap on the prints and smear ribbons kept in the world; the oldest are dropped past it.
static var print_max: int = 1000
## Seconds a print or smear takes to dry from `color` to `dried_color`.
static var print_dry_time: float = 90.0
## Draw order of prints and smears (and the scorch decals): blood's rung, `DrawLayers.BLOOD`; their
## decal layers are added after the first splat, so they draw over it.
static var print_z_index: int = DrawLayers.BLOOD
## Base blood color — dark red, semi-transparent, distinct from the debris "blood" chip tint
## so the two systems stay visually independent.
static var color: Color = Color(0.42, 0.02, 0.03, 0.85)
## What blood dries to (see `BloodSplatConfig.dry_time`).
static var dried_color: Color = Color(0.24, 0.04, 0.03, 0.85)
## Draw order: `DrawLayers.BLOOD`, on the floor and rugs, under what lies there (a body, casings)
## and the standing world.
static var z_index: int = DrawLayers.BLOOD
