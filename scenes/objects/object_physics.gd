extends RefCounted
## Objects domain (private): a piece's physics, `piece.physics`: the Physics components it composes
## — a Knockback child (RigidBody2D adapter, how take_hit shoves it), a Deformable child (damage
## dents/chunks) and, on a solid piece, a BloodSmear child (drags blood out of a puddle) —, its
## collider, built in code and rebuilt to follow the deformed silhouette, and a cloth piece's
## BloodSurface. It holds its piece (a Node, built once with it); the force and deformation MATH
## lives in the Physics domain.

## RigidBody2D adapter; take_hit shoves the body through it.
var knockback: Knockback
## Damage dents/chunks; read by the visuals.
var deformable: Deformable
## The EnvironmentObject whose physics this is.
var _piece: RigidBody2D
## Drags blood out of a puddle as the piece slides through it (solid pieces only).
var _smear: BloodSmear
## A deferred `_rebuild_collider` is already waiting.
var _collider_rebuild_queued := false
## BloodSurface registration of a non-solid piece (a rug soaks blood up).
var _surface_id := -1
## The cut queued with the rebuild, null when none waits.
var _cut: ColliderCuts = null


func _init(piece: RigidBody2D) -> void:
	_piece = piece


## Add the Knockback child (its mass the piece's `weight`), then the Deformable child, whose changes
## rebuild the collider. Created in the piece's _ready() (runtime-shape convention).
func compose() -> void:
	knockback = Knockback.new()
	knockback.mass = _piece.weight
	_piece.add_child(knockback)

	deformable = Deformable.new()
	_piece.add_child(deformable)
	deformable.changed.connect(_on_deformable_changed)


## Add the BloodSmear child of a solid piece, fed its footprint.
func add_smear() -> void:
	_smear = BloodSmear.new()
	_piece.add_child(_smear)
	_smear.set_footprint(
		Deformation.shape_polygon(_piece.shape_type, _piece.size, deformable.impacts)
	)


## A non-solid piece never moves, so its footprint is fixed: blood that reaches cloth (a rug, a mat)
## sinks in (Physics blood); it runs past the rest of the walk-over decor (litter, cables, a puddle,
## a neon tube).
func soak() -> void:
	if _piece.object_material == "fabric":
		_surface_id = BloodSurface.register(
			Rect2(_piece.global_position - _piece.size / 2.0, _piece.size),
			_no_groove,
			true,
		)


## The piece leaves the tree: drop its BloodSurface and a cut still waiting.
func release() -> void:
	BloodSurface.unregister(_surface_id)
	if _cut != null:
		_cut.cancel()


## A rug has no grooves (BloodSurface callback; a porous surface never asks).
func _no_groove(_at: Vector2, _half_width: float) -> float:
	return 0.0


# --- Collider (built in code; rebuilt to follow the deformed silhouette) ---------------


## Rebuild the collider when the silhouette deforms. Deferred: record() runs mid-physics
## (from the projectile), when swapping shapes is disallowed.
## Hits that land before the deferred call runs share it: it rebuilds from the impacts as they stand
## then. Cutting the dented silhouette into convex pieces is the costly part of a rebuild, and a
## blast dents a room's worth of furniture at once: the cut is queued with the rebuild
## (`ColliderCuts`), and the first rebuild of the batch cuts the others on worker threads beside its
## own. The collider changes in its deferred rebuild, into the pieces a cut there would make.
func _on_deformable_changed() -> void:
	if _piece.solid and PhysicsDeformConfig.update_collider and not _collider_rebuild_queued:
		_collider_rebuild_queued = true
		_cut = ColliderCuts.queue(_prepare_cut)
		_rebuild_collider.call_deferred()


## The cut of this piece's silhouette as its dents stand now (on the main thread): a pure job on a
## copy of them.
func _prepare_cut() -> Callable:
	var shape: String = _piece.shape_type
	var footprint: Vector2 = _piece.size
	var dents: Array = deformable.impacts.duplicate(true)
	return func() -> Array: return Deformation.cut_shape(shape, footprint, dents)


## The convex pieces of `poly`, this piece's silhouette now: the queued cut's, or cut here should it
## be of another silhouette.
func _pieces_of(poly: PackedVector2Array) -> Array:
	var cut := _cut
	_cut = null
	if cut != null:
		var made := cut.take()
		if not made.is_empty() and made[0] == poly:
			return made[1]
	return Deformation.convex_pieces(poly)


## Replace the collider(s) with convex pieces of the current deformed polygon.
func _rebuild_collider() -> void:
	_collider_rebuild_queued = false
	var poly := Deformation.shape_polygon(_piece.shape_type, _piece.size, deformable.impacts)
	var shapes := Deformation.shapes_of(_pieces_of(poly))
	if shapes.is_empty():
		return
	_smear.set_footprint(poly)
	for child in _piece.get_children():
		if child is CollisionShape2D:
			child.queue_free()
	for shape in shapes:
		var col := CollisionShape2D.new()
		col.shape = shape
		_piece.add_child(col)


## Build the initial collider from the object's primitive shape.
func build_collider() -> void:
	var col := CollisionShape2D.new()
	match _piece.shape_type:
		"circle":
			var circle := CircleShape2D.new()
			circle.radius = _piece.size.x / 2.0
			col.shape = circle
		"square", "rect":
			var rect := RectangleShape2D.new()
			rect.size = _piece.size
			col.shape = rect
	_piece.add_child(col)
