class_name BloodDecals
extends "res://scenes/physics/mark_layer.gd"
## Physics System, blood: a layer of bloody footprints and smears under a world node, holding every
## print (a polygon) and ribbon (a smear's varying-width trail) as data so thousands of marks cost
## no node each (`mark_layer.gd`). They dry from `BloodConfig.color` to `dried_color` over
## `print_dry_time`, and the oldest are dropped past `BloodConfig.print_max`. Kept off the shared
## Despawner so a trail can't evict casings and splatters. The 3D render lays each as it is made
## (`PhysicsFxHook.print_made`, `ribbon_begun`, `ribbon_grew`).

const NODE_NAME := "BloodDecals"


## The decal layer held by `parent`, or null if none yet.
static func find(parent: Node) -> BloodDecals:
	return parent.get_node_or_null(NODE_NAME) as BloodDecals


## The decal layer under `parent` (the node the marks' maker lives in, like a splatter's parent),
## made on first use. Each parent has its own layer, freed with it.
static func layer(parent: Node) -> BloodDecals:
	return _get_or_make(parent, NODE_NAME, BloodDecals) as BloodDecals


## Add a filled polygon (world space) at `alpha` 0..1 of the blood colour.
func print_at(poly: PackedVector2Array, alpha: float) -> void:
	if poly.size() < 3 or Geometry2D.triangulate_polygon(poly).is_empty():
		return  # the engine can't draw it; drop it rather than log an error
	var born := Engine.get_physics_frames()
	_add(
		{
			"kind": "print",
			"born": born,
			"poly": poly,
			"alpha": alpha,
		},
		BloodConfig.print_max,
	)
	PhysicsFxHook.print_made(poly, alpha)


## Start a smear ribbon at world `point`: `width` px across and `alpha` 0..1 there. Grow it with
## `ribbon_extend`. Drawn as a feathered band whose width and opacity follow its samples. Returns
## the mark.
func ribbon_begin(point: Vector2, width: float, alpha: float) -> Dictionary:
	var mark := {
		"kind": "ribbon", "born": Engine.get_physics_frames(),
		"alpha": 1.0, "points": PackedVector2Array([point]), "widths": PackedFloat32Array([width]),
		"alphas": PackedFloat32Array([alpha]),
	}
	_add(mark, BloodConfig.print_max)
	PhysicsFxHook.ribbon_begun(mark)
	return mark


## Append a sample to ribbon `mark` (a width of 0 closes it to a point). Ignored once the mark was
## dropped.
func ribbon_extend(mark: Dictionary, point: Vector2, width: float, alpha: float) -> void:
	if mark.get("dead", false):
		return
	# Packed arrays are values: take each out, grow it, put it back.
	var points: PackedVector2Array = mark["points"]
	var widths: PackedFloat32Array = mark["widths"]
	var alphas: PackedFloat32Array = mark["alphas"]
	points.append(point)
	widths.append(width)
	alphas.append(alpha)
	mark["points"] = points
	mark["widths"] = widths
	mark["alphas"] = alphas
	PhysicsFxHook.ribbon_grew(mark)


## Number of footprints held.
func print_count() -> int:
	return _count("print")


## Number of smear ribbons held.
func ribbon_count() -> int:
	return _count("ribbon")


## The blood colour of mark `m` right now: dries toward dried_color, alpha scaled by the mark's own.
func color_of(m: Dictionary) -> Color:
	var seconds := BloodConfig.print_dry_time
	var dried := 1.0
	if seconds > 0.0:
		var age := (float(Engine.get_physics_frames() - int(m["born"]))
				/ float(Engine.physics_ticks_per_second))
		dried = clampf(age / seconds, 0.0, 1.0)
	var c: Color = BloodConfig.color.lerp(BloodConfig.dried_color, dried)
	c.a *= float(m["alpha"])
	return c


## How many held marks are of `kind` ("print" or "ribbon").
func _count(kind: String) -> int:
	var n := 0
	for m in _marks:
		if m["kind"] == kind:
			n += 1
	return n
