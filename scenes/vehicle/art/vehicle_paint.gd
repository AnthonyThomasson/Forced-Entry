class_name VehiclePaint extends RefCounted
## One vehicle body being painted (Vehicles domain, the car and van painters through
## vehicle_art.gd): the canvas, its scale from the vehicle's frame, the paint, and the kind with its
## `VehicleConfig.kinds` and `looks` rows. `VehicleArt.paint_parts`' caller makes one per paint.

const Art = preload("res://scenes/vehicle/art/vehicle_art.gd")

## The canvas the body is painted on.
var canvas: PixelCanvas
## The canvas px per vehicle px (`VehicleArt.scale` for the body's length).
var k := 1.0
## The body's paint.
var base := Color.WHITE
## The vehicle's kind and its `VehicleConfig.kinds` and `looks` rows.
var kind: StringName = &""
var row: Dictionary = {}
var look: Dictionary = {}
## Whether this is the flat (albedo) paint of the 3D render (`PixelArt.render_flat`: the canvas has
## no light). A tone a painter picks by hand to stand for light, a lit rim or a ring drawn round a
## raised part, would be baked into the texture and doubled by the 3D lights and the post's
## outline, so a painter draws `lit` instead and skips `ring` while flat.
var flat := false


func _init(on: PixelCanvas, paint: Color, of_kind: StringName) -> void:
	canvas = on
	base = paint
	kind = of_kind
	row = VehicleConfig.kinds[of_kind]
	look = VehicleConfig.looks[of_kind]
	k = Art.scale(on, (row["size"] as Vector2).x)
	flat = on.light == Vector2.ZERO


## `tone` (a hand-picked light or highlight tone) in the lit paint, `plain` (the base tone) in the
## flat one, which carries no baked light.
func lit(tone: Color, plain: Color) -> Color:
	return plain if flat else tone


## Whether a ring drawn round a raised part is wanted: not in the flat paint, where the 3D post
## draws the part's own outline.
func ring() -> bool:
	return not flat
