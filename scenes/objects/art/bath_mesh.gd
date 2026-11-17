extends RefCounted
## Objects domain, the 3D mesh of a bathtub or shower (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`), by `art_opts.style` (`bath_painter.gd`): a `tub` is a
## glazed rim round a basin whose floor and water lie below it, a mixer tap on the rim at the
## left end; a `shower` is a low tray with a glass screen along its front and right side and the
## shower head on its arm from the back wall. In the piece's glaze, the water's colour and the
## taps' metal (`ObjectArtKitchenBathConfig`). Shared by every bath of one look.


## The node a bath `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var mesh := FurnitureMesh.fetch(
		"bath", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	)
	return FurnitureMesh.show(piece, mesh)


## Whether the piece is a shower (`art_opts.style`), else a tub.
static func _shower(spec: FurnitureSpec) -> bool:
	return String(spec.opts.get("style", "tub")) == "shower"


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"style": "shower" if _shower(spec) else "tub",
		"rim": ObjectMeshRoomConfig.bath_rim_height,
		"floor": ObjectMeshRoomConfig.bath_floor_height,
		"water": ObjectMeshRoomConfig.bath_water_height,
		"tray": ObjectMeshRoomConfig.bath_tray_height,
		"screen": ObjectMeshRoomConfig.bath_screen_height,
		"head": ObjectMeshRoomConfig.bath_head_height,
		"water_colour": ObjectArtKitchenBathConfig.bath_water_color,
		"glass": ObjectArtKitchenBathConfig.bath_shower_glass_color,
		"tap": ObjectArtKitchenBathConfig.counter_tap_color,
	}


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	if _shower(spec):
		_shower_mesh(spec, kit)
	else:
		_tub(spec, kit)
	return kit.build()


## The rim round a basin, its floor, its water and the tap at the left end.
static func _tub(spec: FurnitureSpec, kit: MeshKit) -> void:
	var base := spec.color
	var w := spec.size.x
	var d := spec.size.y
	var rim_h := ObjectMeshRoomConfig.bath_rim_height
	var lip := maxf(4.0, floorf(minf(w, d) / 12.0))
	var whole := Rect2(0, 0, w, d)
	var basin := whole.grow(-lip)
	for strip in FurnitureSpec.ring(whole, basin):
		var rim := spec.area(strip.position.x, strip.position.y, strip.size.x, strip.size.y)
		kit.box(
			MeshKit.volume(rim, 0.0, rim_h),
			base,
			MeshKit.tone(base, &"highlight"),
		)
	kit.box(
		MeshKit.volume(spec.area(basin.position.x, basin.position.y, basin.size.x, basin.size.y),
			0.0, ObjectMeshRoomConfig.bath_floor_height),
		MeshKit.tone(base, &"dark"),
	)
	var water := basin.grow(-3.0)
	kit.box(
		MeshKit.volume(spec.area(water.position.x, water.position.y, water.size.x, water.size.y),
			ObjectMeshRoomConfig.bath_floor_height,
			ObjectMeshRoomConfig.bath_water_height - ObjectMeshRoomConfig.bath_floor_height),
		ObjectArtKitchenBathConfig.bath_water_color,
	)
	_taps(spec, kit, lip)


## The mixer tap on the rim at the left end: a spout and a handle either side of it.
static func _taps(spec: FurnitureSpec, kit: MeshKit, lip: float) -> void:
	var metal := ObjectArtKitchenBathConfig.counter_tap_color
	var rim_h := ObjectMeshRoomConfig.bath_rim_height
	var cy := floorf(spec.size.y / 2.0)
	kit.box(MeshKit.volume(spec.area(1, cy - 1, lip + 4, 2), rim_h, 4.0), metal)
	for dy: float in [-5.0, 5.0]:
		kit.box(
			MeshKit.volume(spec.area(floorf(lip / 2.0), cy + dy - 1.0, 2, 2), rim_h, 6.0),
			metal,
		)


## The tray, the glass along the front and right side, the head on its arm.
static func _shower_mesh(spec: FurnitureSpec, kit: MeshKit) -> void:
	var base := spec.color
	var w := spec.size.x
	var d := spec.size.y
	var glass := ObjectArtKitchenBathConfig.bath_shower_glass_color
	var screen := ObjectMeshRoomConfig.bath_screen_height
	var head_at := ObjectMeshRoomConfig.bath_head_height
	var metal := ObjectArtKitchenBathConfig.counter_tap_color
	kit.box(
		MeshKit.volume(spec.area(0, 0, w, d), 0.0, ObjectMeshRoomConfig.bath_tray_height),
		MeshKit.tone(base, &"dark"),
		base,
	)
	kit.box(MeshKit.volume(spec.area(0, d - 2, w, 2), 0.0, screen), glass)
	kit.box(MeshKit.volume(spec.area(w - 2, 0, 2, d - 2), 0.0, screen), glass)
	var head := Vector2(roundf(w * 0.22), roundf(d * 0.16))
	kit.box(MeshKit.volume(spec.area(head.x - 1, 0, 2, 2), 0.0, head_at + 6.0), metal)
	kit.box(MeshKit.volume(spec.area(head.x - 1, 0, 2, head.y), head_at + 4.0, 2.0), metal)
	var at := head - spec.half()
	kit.cylinder(Vector3(at.x, head_at + 3.0, at.y), maxf(2.0, floorf(w / 18.0)), 2.0, metal)
