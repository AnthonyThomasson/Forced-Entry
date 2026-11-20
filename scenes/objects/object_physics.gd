extends RefCounted
## Objects domain (private): a piece's physics, `piece.physics`: the Physics components it composes
## — a Knockback child (its mass, how take_hit shoves it), a Deformable child (damage dents/chunks)
## and, on a solid piece, a BloodSmear child (drags blood out of a puddle) —, the silhouette its
## dents leave (laid under the smear, and what its mesh follows: `reshaped`) and a cloth piece's
## BloodSurface. It holds its piece (a Node, built once with it); the force and deformation MATH
## lives in the Physics domain. A piece has no collider: its body is its 3D twin, built from the
## parts of `PieceHeights` (`ObjectTwins`), which a dent does not reshape.

## Knockback child; take_hit shoves the body through it.
var knockback: Knockback
## Damage dents/chunks; read by the furniture rig and the silhouette rebuild.
var deformable: Deformable
## The EnvironmentObject whose physics this is.
var _piece: Node2D
## Drags blood out of a puddle as the piece slides through it (solid pieces only).
var _smear: BloodSmear
## A deferred `_rebuild_silhouette` is already waiting.
var _rebuild_queued := false
## BloodSurface registration of a non-solid piece (a rug soaks blood up).
var _surface_id := -1
## Whether the footprint is the hull of a tipped 3D body (`set_tipped_footprint`): the dents are
## kept and the silhouette is laid again when the piece is upright (`restore_footprint`).
var _tipped := false


func _init(piece: Node2D) -> void:
	_piece = piece


## Add the Knockback child (its mass the piece's `weight`), then the Deformable child, whose changes
## rebuild the silhouette. Created in the piece's _ready() (runtime-shape convention).
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


## The piece leaves the tree: drop its BloodSurface.
func release() -> void:
	BloodSurface.unregister(_surface_id)


## A rug has no grooves (BloodSurface callback; a porous surface never asks).
func _no_groove(_at: Vector2, _half_width: float) -> float:
	return 0.0


# --- Silhouette (rebuilt to follow the deformed piece) ----------------------------------


## Rebuild the silhouette when the piece deforms. Deferred: record() runs mid-physics (from the
## projectile). Hits that land before the deferred call runs share it: it lays the silhouette from
## the impacts as they stand then, and the mesh built from them is built again (`reshaped`).
func _on_deformable_changed() -> void:
	if (_piece.solid and PhysicsDeformConfig.update_collider and not _rebuild_queued
			and not _tipped):
		_rebuild_queued = true
		_rebuild_silhouette.call_deferred()


## Lay the smear across the piece's silhouette as its dents have left it and tell the mesh.
func _rebuild_silhouette() -> void:
	_rebuild_queued = false
	if not is_instance_valid(_piece) or not _piece.is_inside_tree() or _tipped:
		return
	_smear.set_footprint(_silhouette())
	_piece.reshape()


## The piece's outline (its own frame) as its dents leave it.
func _silhouette() -> PackedVector2Array:
	return Deformation.shape_polygon(_piece.shape_type, _piece.size, deformable.impacts)


## The footprint is the single convex polygon `hull` (the projection of the tipped piece's 3D shape,
## in the piece's frame) in place of the silhouette. (A nav re-bake finds the piece's new footprint
## from its twin's pose: `NavPieces`.)
func set_tipped_footprint(hull: PackedVector2Array) -> void:
	_piece.footprint_stamp += 1
	_tipped = true
	_smear.set_footprint(hull)


## The piece is upright again: its silhouette as its dents have left it, as a rebuild makes it.
func restore_footprint() -> void:
	if not _tipped:
		return
	_tipped = false
	_piece.footprint_stamp += 1
	_rebuild_queued = false
	_smear.set_footprint(_silhouette())
	_piece.reshape()  # its dents may have changed while it lay
