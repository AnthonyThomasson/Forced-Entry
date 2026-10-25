class_name Deformable extends Node
## Physics System: reusable damage-deformation component for a single primitive-shaped body
## (furniture, a character or a vehicle). Add it as a child of the drawable body; on each
## `record(hit)` it converts the world contact into a local impact (dent, or a carved "missing
## piece" for a hard hit) and emits `changed`, so the owner can redraw its silhouette and, if it
## wants, rebuild its collider from the SAME deformed polygon (via the Deformation static helper).
## Per-body fields (max_depth / allow_chunks / max_impacts) let a small body dent gently without
## folding. Walls keep their own per-segment recording instead (their geometry isn't a
## single centered shape), but they build each impact through the same Deformation.new_impact /
## push_impact and PhysicsDeformConfig knobs.

## Emitted after an impact is recorded, so visuals redraw and the collider rebuilds.
signal changed

## Recorded impacts (local space) that deform the drawn silhouette, and the accumulated
## damage (drives fill darkening). Read by the owner's visuals + collider rebuild.
var impacts: Array = []
## Accumulated dealt damage (drives fill darkening).
var damage_total := 0.0
## Deepest a single dent may cave (px). Defaults to the furniture value; a small body (a
## character) sets this lower so a dent stays a fraction of its radius.
var max_depth := PhysicsDeformConfig.max_depth
## Whether a hard hit carves a jagged "missing piece". Furniture allows it; a small body
## disables it, since a chunk reach spanning the whole silhouette self-intersects it.
var allow_chunks := true
## How many impacts are remembered (oldest dropped past this). A small body keeps fewer, so
## dents from many directions can't pile up and pinch the silhouette toward its core.
var max_impacts := PhysicsDeformConfig.max_impacts
## The deformed body (parent).
var _body: Node2D


func _ready() -> void:
	_body = get_parent()


## Record a damage impact from a HitInfo. Stored in local space so it rides along as the
## body is shoved/spun. `turn` is how far the owner draws the body turned beyond its node
## rotation (a character facing its aim); the impact is stored un-turned, so the owner turns it
## back when drawing and the dent stays on the part that was hit.
func record(hit: HitInfo, turn: float = 0.0) -> void:
	var xf := _body.global_transform.affine_inverse()
	var local_pos := (xf * hit.position).rotated(-turn)
	var inward := xf.basis_xform(-hit.normal).normalized().rotated(-turn)  # into the surface
	if inward.length() < 0.01:
		inward = -local_pos.normalized() if local_pos.length() > 0.01 else Vector2.DOWN
	var dent := DentLimits.new()
	dent.max_depth = max_depth
	dent.allow_chunks = allow_chunks
	var impact := Deformation.new_impact(local_pos, inward, hit.damage, hit.blood, dent)
	Deformation.push_impact(impacts, impact, max_impacts)
	damage_total += hit.damage
	changed.emit()
