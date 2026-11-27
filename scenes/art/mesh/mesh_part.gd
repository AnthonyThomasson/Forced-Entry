class_name MeshPart
extends RefCounted
## Art domain, one part of a `PartSkin` (interface 12): a solid, what it wears and where it is.
## The part is plain data. The skin reads `mesh`, `tint`, `texture`, `rect`, `cutout` and `visible`
## when it is dressed, and `transform` each time it is posed. A solid and a texture once dressed are
## never written again (`PartSkin` keeps what it read of them).

## The solid, in its own frame: one surface of the mesh kit, unindexed, with vertex colours.
var mesh: Mesh
## What the solid's vertex colours are multiplied by (an sRGB colour, white: as they are).
var tint := Color.WHITE
## The art on it (null: plain colour), the footprint the art covers in the solid's own frame
## (model units, `MeshNodes.textured`'s `uv_rect`) and whether a clear texel draws nothing.
var texture: Texture2D
var rect := Rect2()
var cutout := false
## Whether it is drawn at all (set before the skin is dressed).
var visible := true
## Where it is, in the frame of the skin's node.
var transform := Transform3D.IDENTITY
## `transform`'s origin.
var position: Vector3:
	get:
		return transform.origin
