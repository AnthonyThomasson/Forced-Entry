class_name InkMark
extends RefCounted
## Physics domain, one mark lying on the 3D floor (a splat, a print, a smear, a scorch): flat
## triangles (3D units, up facing) with a colour a vertex, filed in the chunk of its place
## (`InkFx`, `InkChunk`). Built once; a drying mark is painted again at each step of its drying, a
## smear that grows is built again.

## What it is: `SPLAT`, `PRINT`, `RIBBON` or `SCORCH`.
enum Kind {
	SPLAT,
	PRINT,
	RIBBON,
	SCORCH,
}

## The kind and the chunk cell the mark is filed in.
var kind := Kind.SPLAT
var cell := Vector2i.ZERO
## The triangles (3D units) and a colour for each vertex (linear, as the mesh kit's are). The first
## `body` vertices are the mark's body, the rest the lighter fleck over it (a fresh splat's wet
## highlight).
var verts := PackedVector3Array()
var colors := PackedColorArray()
var body := 0
## The physics frame it was made on, which its drying counts from, the seconds its drying takes
## (0: it does not dry, or is dry at once: `InkFx`) and the step of its drying it is painted at
## (`PhysicsInkConfig.dry_steps` when it is dry).
var born := 0
var dry_time := 0.0
var step := 0
## A print's own opacity (0..1) and a splat's fleck (the wet highlight's colour, the art's sRGB
## colour with its opacity).
var alpha := 1.0
var fleck := Color.TRANSPARENT
## The 2D thing it shows: a splat's node (an instance id) or a smear's mark (the 2D layer's own
## dictionary, read again as it grows).
var node_id := 0
var source: Dictionary = {}
