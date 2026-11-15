extends RefCounted
## Objects domain, the 3D mesh of the garage's parked car (#193 phase 2; the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): the furniture prop, a solid anchored-by-weight piece
## the garage recipe places, not the Vehicles domain's drivable car. At the piece's own footprint
## and `car_painter.gd`'s proportions, nose toward the front (+y): four tyres peeking out at the
## corners (lying cylinders), a rounded body in the beater's paint (its colour taken to
## `ObjectArtOutdoorConfig.car_beater_color` by `car_beater`), a raised roof between the windscreen
## and the rear window, tinted glass, headlights and a grille up front, tail lights behind and the
## wing mirrors. Nothing on it glows (the 2D car's lamps are painted, not lit).

## How far the glass, the lamps and the mirrors stand proud of the body.
const PROUD := 0.5


## The node a car `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	return FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"car", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	))


## The paint the body wears: the piece's colour taken toward the beater's rust-brown.
static func paint(spec: FurnitureSpec) -> Color:
	return spec.color.lerp(
		ObjectArtOutdoorConfig.car_beater_color,
		ObjectArtOutdoorConfig.car_beater,
	)


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"paint": paint(spec),
		"sizes": [
			ObjectMeshCarConfig.tyre_radius, ObjectMeshCarConfig.body_base,
			ObjectMeshCarConfig.body_top, ObjectMeshCarConfig.roof_top,
			ObjectMeshCarConfig.glass_proud,
		],
		"colours": [
			ObjectArtOutdoorConfig.car_tyre_color, ObjectArtOutdoorConfig.car_glass_color,
			ObjectArtOutdoorConfig.car_light_color,
		],
	}


## The four tyres, the body, the cabin and what is on them, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var tyre_w := maxf(4.0, roundf(spec.size.x * 0.1))
	_tyres(spec, kit, tyre_w)
	var rect := Rect2(tyre_w - 2.0, 1.0, spec.size.x - (tyre_w - 2.0) * 2.0, spec.size.y - 2.0)
	var body := paint(spec)
	var base := ObjectMeshCarConfig.body_base
	kit.extrude(
		FurnitureSpec.rounded(Rect2(rect.position - spec.half(), rect.size), rect.size.x * 0.1),
		base,
		ObjectMeshCarConfig.body_top - base,
		body,
		body.lightened(0.04),
	)
	_cabin(spec, kit, rect)
	_lamps(spec, kit, rect)
	return kit.build()


## The raised cabin between the windscreen and the rear window, its side windows and the two panes
## of glass laid over the body.
static func _cabin(spec: FurnitureSpec, kit: MeshKit, rect: Rect2) -> void:
	var d := spec.size.y
	var top := ObjectMeshCarConfig.body_top
	var roof := ObjectMeshCarConfig.roof_top
	var body := paint(spec)
	var glass := ObjectArtOutdoorConfig.car_glass_color
	var cabin := Rect2(
		rect.position.x + 9.0,
		roundf(d * 0.25),
		rect.size.x - 18.0,
		roundf(d * 0.31),
	)
	kit.extrude(
		FurnitureSpec.rounded(Rect2(cabin.position - spec.half(), cabin.size), 6.0),
		top,
		roof - top,
		body.lightened(0.04),
		body.lightened(0.1),
	)
	var panes := [
		spec.area(rect.position.x + 8.0, roundf(d * 0.56), rect.size.x - 16.0, roundf(d * 0.12)),
		spec.area(rect.position.x + 10.0, roundf(d * 0.16), rect.size.x - 20.0, roundf(d * 0.09)),
	]
	for pane: Rect2 in panes:
		kit.box(MeshKit.volume(pane, top, ObjectMeshCarConfig.glass_proud), glass)
	var proud := ObjectMeshCarConfig.glass_proud
	for x: float in [cabin.position.x - proud, cabin.end.x]:
		var side := spec.area(x, cabin.position.y + 3.0, proud, cabin.size.y - 7.0)
		kit.box(MeshKit.volume(side, top + 2.0, roof - top - 4.0), glass)


## The four tyres, `tyre_w` wide, at the painter's places along the car, each a cylinder on its
## side with the axle along x.
static func _tyres(spec: FurnitureSpec, kit: MeshKit, tyre_w: float) -> void:
	var radius := ObjectMeshCarConfig.tyre_radius
	var colour := ObjectArtOutdoorConfig.car_tyre_color
	var tyre_h := maxf(6.0, roundf(spec.size.y * 0.14))
	for fy: float in [0.14, 0.72]:
		for x: float in [0.0, spec.size.x - tyre_w]:
			var at := Vector2(
				x + tyre_w * 0.5,
				roundf(spec.size.y * fy) + tyre_h * 0.5,
			) - spec.half()
			spec.level(kit, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(at.x, radius, at.y)))
			kit.cylinder(Vector3(0.0, -tyre_w * 0.5, 0.0), radius, tyre_w, colour)
	spec.level(kit)


## The headlights and the grille at the nose, the tail lights at the back and a wing mirror each
## side.
static func _lamps(spec: FurnitureSpec, kit: MeshKit, rect: Rect2) -> void:
	var d := spec.size.y
	var proud := ObjectMeshCarConfig.glass_proud
	var cx := spec.size.x * 0.5
	var lamp_h := ObjectMeshCarConfig.body_top - 12.0
	for side: float in [-1.0, 1.0]:
		var x := cx + side * roundf(rect.size.x * 0.32) - 5.0
		kit.box(
			MeshKit.volume(spec.area(x, rect.end.y - 0.0, 10, proud), lamp_h, 5.0),
			ObjectArtOutdoorConfig.car_light_color,
		)
		kit.box(
			MeshKit.volume(spec.area(x, rect.position.y - proud, 10, proud), lamp_h, 4.0),
			Color(0.8, 0.12, 0.1),
		)
		var mirror_x := rect.position.x - 4.0 if side < 0.0 else rect.end.x - 1.0
		kit.box(
			MeshKit.volume(
				spec.area(mirror_x, roundf(d * 0.55), 5, 4),
				ObjectMeshCarConfig.body_top - 6.0,
				4.0,
			),
			paint(spec),
		)
	var grille := roundf(rect.size.x * 0.36)
	kit.box(
		MeshKit.volume(
			spec.area(cx - grille * 0.5, rect.end.y - 0.0, grille, proud),
			ObjectMeshCarConfig.body_base + 4.0,
			5.0,
		),
		MeshKit.tone(paint(spec), &"outline"),
	)
