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


func _init(on: PixelCanvas, paint: Color, of_kind: StringName) -> void:
	canvas = on
	base = paint
	kind = of_kind
	row = VehicleConfig.kinds[of_kind]
	look = VehicleConfig.looks[of_kind]
	k = Art.scale(on, (row["size"] as Vector2).x)
