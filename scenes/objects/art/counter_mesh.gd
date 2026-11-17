extends RefCounted
## Objects domain, the 3D mesh of a counter, island or sink (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint, a carcass under a top in
## the piece's colour, a backsplash rising along the back, and for a sink a basin sunk into the top
## (a floor lower than its rim) with a mixer tap on the backsplash side
## (`counter_painter.gd`: `basin` "none" | "single" | "deep", `backsplash`;
## `ObjectArtKitchenBathConfig.counter_*`). Shared by every counter of one look.

const OPTIONS := ["basin", "backsplash", "height"]


## The node a counter `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"counter", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## How tall a counter stands: its `art_opts.height`, else the standard.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	return float(own) if own is float or own is int else ObjectMeshKitchenConfig.counter_height


## The painter's basin option: "none", "single" or "deep".
static func _basin_of(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("basin", "none"))


## The backsplash's depth along the back (0 when it is off).
static func splash_of(spec: FurnitureSpec) -> float:
	var on: bool = spec.opts.get("backsplash", ObjectArtKitchenBathConfig.counter_backsplash)
	return maxf(2.0, roundf(spec.size.y * 0.07)) if on else 0.0


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"basin": _basin_of(spec),
		"splash": splash_of(spec),
		"height": height_of(spec),
		"top": ObjectMeshKitchenConfig.counter_top,
		"rise": ObjectMeshKitchenConfig.counter_splash,
		"single": ObjectMeshKitchenConfig.counter_basin,
		"deep": ObjectMeshKitchenConfig.counter_deep_basin,
		"tap": ObjectArtKitchenBathConfig.counter_tap_color,
	}


## The solids of the piece, built once per cache key: the carcass, the top (with a basin cut into
## it for a sink) and the backsplash.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var base := spec.color
	var h := height_of(spec)
	var splash := splash_of(spec)
	var sink := _sink_of(spec)
	var slab := maxf(ObjectMeshKitchenConfig.counter_top, sink)
	var kit := spec.kit()
	var deep := _basin_of(spec) == "deep"
	var floor_colour := base.darkened(0.16 if deep else 0.08)
	kit.box(
		MeshKit.volume(spec.area(0, 0, spec.size.x, spec.size.y), 0.0, h - slab),
		MeshKit.tone(base, &"dark"),
		floor_colour if sink > 0.0 else base,
	)
	if sink <= 0.0:
		kit.box(
			MeshKit.volume(spec.area(0, 0, spec.size.x, spec.size.y), h - slab, slab),
			MeshKit.tone(base, &"dark"),
			base,
		)
	else:
		var basin_rect := _basin_rect(spec, splash)
		for strip in FurnitureSpec.ring(Rect2(0, 0, spec.size.x, spec.size.y), basin_rect):
			var rect := spec.area(strip.position.x, strip.position.y, strip.size.x, strip.size.y)
			kit.box(MeshKit.volume(rect, h - slab, slab), MeshKit.tone(base, &"dark"), base)
		_tap(spec, kit, basin_rect, splash, h)
	if splash > 0.0:
		kit.box(
			MeshKit.volume(
				spec.area(0, 0, spec.size.x, splash), h, ObjectMeshKitchenConfig.counter_splash
			),
			MeshKit.tone(base, &"dark"),
			MeshKit.tone(base, &"light"),
		)
	return kit.build()


## How far the basin sinks below the rim (0 for none).
static func _sink_of(spec: FurnitureSpec) -> float:
	match _basin_of(spec):
		"deep":
			return ObjectMeshKitchenConfig.counter_deep_basin
		"none":
			return 0.0
	return ObjectMeshKitchenConfig.counter_basin


## The basin's rectangle in the counter's frame, as the painter lays it.
static func _basin_rect(spec: FurnitureSpec, splash: float) -> Rect2:
	var margin := maxf(3.0, roundf(spec.size.x * 0.16))
	var top := splash + maxf(3.0, roundf(spec.size.y * 0.12))
	var depth := maxf(4.0, spec.size.y - top - maxf(3.0, roundf(spec.size.y * 0.1)))
	return Rect2(margin, top, spec.size.x - margin * 2.0, depth)


## A mixer tap standing on the rim at the back of the basin, its spout over the basin.
static func _tap(
	spec: FurnitureSpec,
	kit: MeshKit,
	basin: Rect2,
	splash: float,
	height: float,
) -> void:
	var metal := ObjectArtKitchenBathConfig.counter_tap_color
	var x := basin.position.x + basin.size.x * 0.5 - 1.0
	var y := maxf(0.0, splash - 1.0)
	kit.box(MeshKit.volume(spec.area(x, y, 2, 2), height, 8.0), metal)
	kit.box(
		MeshKit.volume(spec.area(x, y, 2, basin.position.y - y + 3.0), height + 6.5, 1.5),
		metal,
	)
