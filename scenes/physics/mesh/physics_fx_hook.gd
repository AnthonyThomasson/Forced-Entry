class_name PhysicsFxHook
extends RefCounted
## Physics domain, the 2D code's way of telling the 3D render what it made (#193 phase 2): static
## calls from the places that spawn debris, hit particles, blood and explosions, answered by the
## installed `FxLayer` (`PhysicsMeshes.install`). With none installed (the 2D render, or a test
## world with no 3D view) each call is one check and nothing else, so the 2D game is as it was.

## The layer being told, null in the 2D render. Untyped, so a layer freed with its world is told
## no more.
static var sink: Object
## The height (0..100, a hit's `HitInfo.height`; negative: the floor) of the hit whose debris and
## bursts are being spawned, which only the 3D render shows: `Physics.spawn_debris` sets it around
## its calls.
static var hit_height := -1.0


## Whether a layer is listening.
static func active() -> bool:
	return is_instance_valid(sink)


## A chip was thrown off a surface, at the hit's height (`hit_height`).
static func chip_flew(chip: Node2D) -> void:
	if is_instance_valid(sink):
		sink.chip_flew(chip, hit_height)


## A flying chip came to rest.
static func chip_landed(chip: Node2D) -> void:
	if is_instance_valid(sink):
		sink.chip_landed(chip)


## A burst of hit particles was made: `emitter` is the 2D `CPUParticles2D` (its amount, spread,
## speeds, sizes, life and colour say what the 3D one shows), `spark` whether it is the metal
## style's lit-whatever-the-light kind, `height` the hit's 0..100 height (negative: the floor).
static func burst_made(emitter: CPUParticles2D, spark: bool, height: float) -> void:
	if is_instance_valid(sink):
		sink.burst_made(emitter, spark, height)


## A splat of blood was built (`splat` is the 2D `BloodSplat`, its outlines in `shapes`).
static func splat_made(splat: Node2D) -> void:
	if is_instance_valid(sink):
		sink.splat_made(splat)


## A footprint was stamped: a polygon in world px at `alpha` of the blood colour.
static func print_made(poly: PackedVector2Array, alpha: float) -> void:
	if is_instance_valid(sink):
		sink.print_made(poly, alpha)


## A smear ribbon began (`source` is the 2D layer's own mark) or grew.
static func ribbon_begun(source: Dictionary) -> void:
	if is_instance_valid(sink):
		sink.ribbon_begun(source)


## A smear ribbon grew.
static func ribbon_grew(source: Dictionary) -> void:
	if is_instance_valid(sink):
		sink.ribbon_grew(source)


## A frag's scorch was burned: its rows in world px and a colour for each.
static func scorch_burned(rects: Array[Rect2], tones: Array[Color]) -> void:
	if is_instance_valid(sink):
		sink.scorch_burned(rects, tones)


## A bleed-out pool began (`pool` is the 2D `BloodPool`) and its fill changed.
static func pool_made(pool: Node2D) -> void:
	if is_instance_valid(sink):
		sink.pool_made(pool)


## A bleed-out pool's fill changed.
static func pool_changed(pool: Node2D) -> void:
	if is_instance_valid(sink):
		sink.pool_changed(pool)


## A grenade's burst went off at `at` (world px) in the look `row` (`PhysicsExplosionConfig.looks`).
static func blast_made(at: Vector2, row: Dictionary) -> void:
	if is_instance_valid(sink):
		sink.blast_made(at, row)
