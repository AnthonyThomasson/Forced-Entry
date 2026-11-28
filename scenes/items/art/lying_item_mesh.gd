class_name LyingItemMesh
extends Node3D
## Items domain, an item loose in the world on the 3D floor (`domain-art/meshes.md`):
## what the mirror shows a `DroppedItem` or a `ThrownGrenade` by. It is the mesh the item art gives
## for a loose item (`ItemArt.dropped_mesh`: a gun's side profile lifted, shared by kind and look),
## wearing the item's flat art (`dropped_texture`) on its top, laid on the floor about the middle of
## its footprint, so the node's origin, which the mirror places at the item's 2D place, is the
## middle of what lies there. Its own pivot turns it along the item's angle and lifts it by the
## item's height; the item says when either changed (`shifted`), so a lying item is neither written
## nor updated.

## What turns and lifts the mesh, and the mesh laid in it.
var _pivot := Node3D.new()
## The item (a `DroppedItem` or a `ThrownGrenade`) the mesh follows.
var _source: Node2D


## The mesh that shows `source` (a node with an `item`, `altitude()`, `heading()` and `shifted`), or
## null when its item has no loose mesh. A builder for `MeshFollower.track_group`.
static func build(source: Node2D) -> Node3D:
	var item: Item = source.get(&"item")
	var flipped: bool = source.has_method(&"flipped") and source.flipped()
	var mesh: Mesh = item.art.dropped_mesh(flipped) if item != null else null
	if mesh == null:
		return null
	var node := LyingItemMesh.new()
	node._source = source
	node._show(item.art, mesh, flipped)
	source.shifted.connect(node._follow)
	node._follow()
	return node


## Lay `mesh` (of `art`'s item) in the pivot wearing the item's flat art, its footprint's middle on
## the origin and its underside on the floor.
func _show(art: ItemArt, mesh: Mesh, flipped: bool) -> void:
	var box := mesh.get_aabb()
	var shown := MeshNodes.instance(mesh)
	var glow := ItemMeshConfig.lying_brighten
	MeshNodes.textured(
		shown, art.dropped_texture(flipped), art.dropped_rect(), { "tint": Color(glow, glow, glow) }
	)
	MeshNodes.figure(shown)  # a speck at zoom 1: the silhouette only, as a held item
	shown.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	_pivot.add_child(shown)
	add_child(_pivot)


## Turn the pivot along the item's angle (its 2D muzzle `(cos a, sin a)` is 3D `(cos a, 0, sin a)`
## and the mesh's front is +z) and lift it by the item's height.
func _follow() -> void:
	_pivot.rotation.y = PI * 0.5 - _source.heading()
	_pivot.position.y = _source.altitude() * RenderConfig.unit
