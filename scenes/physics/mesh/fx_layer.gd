class_name FxLayer
extends Node3D
## Physics domain, the 3D look of the debris, hit particles, blood and explosions (#193 phase 2;
## `domain-physics/meshes.md`): one layer under the 3D mirror that shows what the 2D Physics code
## makes. The 2D code tells it as it makes each thing (`PhysicsFxHook`: nothing is told while no
## layer is installed, so the 2D render pays one check), and the layer shows it by pooled batches
## and meshes that are made once, so nothing is allocated while the game runs. It processes only
## while
## something moves (chips in the air, a burst's bits, a growing pool, a blast): at rest nothing
## runs and nothing is written. Each kind of effect is a part of its own (`DebrisFx` ...), bounded
## by the `Despawner`'s cap as the 2D one is.

## The chips, the bits and sparks of a burst, the marks lying on the floor and the pools.
var debris: DebrisFx
var bursts: BurstFx
var ink: InkFx
var pools: PoolInk
var blasts: BlastFx


func _init() -> void:
	name = "FxLayer"


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	var chips := debris.process(delta)
	var bits := bursts.process(delta)
	ink.process()
	var waiting := pools.process(delta)
	var blast := blasts.process(delta)
	set_process(chips or bits or waiting or blast or ink.pending())


## Build the parts: `cap` is the most things of a kind the world keeps (the `Despawner`'s), `world`
## the ground they lie on and their random numbers.
func build(cap: int, world: FxWorld) -> void:
	debris = DebrisFx.new(self, cap, world)
	bursts = BurstFx.new(self, world)
	ink = InkFx.new(self, cap, world)
	ink.went_dry.connect(set_process.bind(true))
	pools = PoolInk.new(self, world)
	blasts = BlastFx.new(self, world)


## A chip left a surface at `height` (0..100 cover scale, negative: the floor): it flies.
func chip_flew(chip: Node2D, height: float) -> void:
	debris.fly(chip, height)
	set_process(true)


## A flying chip came to rest.
func chip_landed(chip: Node2D) -> void:
	debris.land(chip)


## A burst of hit particles (`HitParticles.spawn`'s dict) left a surface.
func burst_made(burst: Dictionary) -> void:
	bursts.burst(burst)
	set_process(true)


## A splat of blood was built (`splat` is the 2D `BloodSplat`).
func splat_made(splat: Node2D) -> void:
	ink.splat_made(splat)
	set_process(true)


## A footprint was stamped (a polygon in world px, at `alpha` of the blood colour).
func print_made(poly: PackedVector2Array, alpha: float) -> void:
	ink.print_made(poly, alpha)
	set_process(true)


## A smear ribbon began or grew (`source` is the 2D layer's own mark).
func ribbon_begun(source: Dictionary) -> void:
	ink.ribbon_begun(source)
	set_process(true)


## A smear ribbon grew.
func ribbon_grew(source: Dictionary) -> void:
	ink.ribbon_grew(source)
	set_process(true)


## A frag's scorch was burned (rows of world px and a colour for each).
func scorch_burned(rects: Array[Rect2], tones: Array[Color]) -> void:
	ink.scorch_burned(rects, tones)
	set_process(true)


## A grenade's burst went off at `at` (world px) in the look `row`.
func blast_made(at: Vector2, row: Dictionary) -> void:
	blasts.burst(at, row)
	set_process(true)


## A bleed-out pool began, and its fill changed.
func pool_made(pool: Node2D) -> void:
	pools.pool_made(pool)
	set_process(true)


## A pool's fill changed.
func pool_changed(pool: Node2D) -> void:
	pools.pool_changed(pool)
	set_process(true)
