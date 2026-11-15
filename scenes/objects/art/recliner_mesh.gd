extends RefCounted
## Objects domain, the 3D mesh of a recliner (#193 phase 2; the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): at the piece's own footprint, head toward the back (-y), a dark frame
## under four padded sections (headrest, backrest, seat, leg rest: `recliner_painter.gd`'s
## fractions) and an armrest each side. `kind` `rig` (the netrunner's jack-in chair) pads in the
## piece's colour and has a halo of LEDs round the headrest, glowing; `surgical` pads in pale vinyl,
## is strapped, and carries the surgeon's lamp on an arm over the chest, its lens glowing. Shared by
## every recliner of one look; the glow is a node of its own (`FurnitureRig`).

const Decay = preload("res://scenes/objects/art/decay.gd")
const SECTIONS := [[0.0, 0.18], [0.2, 0.52], [0.54, 0.74], [0.76, 1.0]]
const LEDS := 10


## The node a recliner `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"recliner", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	var glow := FurnitureMesh.fetch_glow(
		"recliner", spec, tuning, func() -> Mesh: return _glow(spec)
	)
	rig.add_glow(glow, _glow_color(spec))
	return rig


## Whether the chair is the surgical one (`art_opts.kind`), else the netrunner's rig.
static func _surgical(spec: FurnitureSpec) -> bool:
	return String(spec.opts.get("kind", "rig")) == "surgical"


## The colour the glowing part glows in: the surgeon's lamp, or the rig's screens' green or neon.
static func _glow_color(spec: FurnitureSpec) -> Color:
	if _surgical(spec):
		return ObjectArtClinicConfig.recliner_lamp_color
	return Decay.screen_color(spec.opts)


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"kind": spec.opts.get("kind", "rig"),
		"neon": String(spec.opts.get("neon", "")),
		"frame": ObjectMeshChairConfig.recliner_frame_height,
		"heights": [
			ObjectMeshChairConfig.recliner_head_height,
			ObjectMeshChairConfig.recliner_back_height,
			ObjectMeshChairConfig.recliner_seat_height,
			ObjectMeshChairConfig.recliner_leg_height,
		],
		"arm": ObjectMeshChairConfig.recliner_arm_height,
		"surgical": [
			ObjectMeshClinicConfig.head_height,
			ObjectMeshClinicConfig.back_height,
			ObjectMeshClinicConfig.foot_height,
		],
		"lamp": ObjectMeshChairConfig.recliner_lamp_height,
		"vinyl": ObjectArtClinicConfig.recliner_vinyl_color,
		"lamp_colour": ObjectArtClinicConfig.recliner_lamp_color,
		"frame_colour": ObjectArtClinicConfig.recliner_frame_color,
		"dark": ObjectArtTechConfig.tech_dark_color,
	}


## The solids of the piece, built once per cache key: the frame, the pads, the armrests and, for
## the surgical chair, its straps and lamp.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(
			spec.area(4, 2, spec.size.x - 8, spec.size.y - 4),
			0.0,
			ObjectMeshChairConfig.recliner_frame_height,
		),
		ObjectArtTechConfig.tech_dark_color,
	)
	var inner := Rect2(7, 4, spec.size.x - 14, spec.size.y - 8)
	_pads(spec, kit, inner)
	for x: float in [1.0, spec.size.x - 5.0]:
		kit.box(
			MeshKit.volume(
				spec.area(x, spec.size.y * 0.36, 4, spec.size.y * 0.3),
				0.0,
				ObjectMeshChairConfig.recliner_arm_height,
			),
			ObjectArtClinicConfig.recliner_frame_color,
		)
	if _surgical(spec):
		_straps_and_lamp(spec, kit, inner)
	return kit.build()


## The four padded sections (headrest, backrest, seat, leg rest) down the chair's `inner` rect. The
## rig's are flat blocks; the surgical chair's back is a slope up toward the head and its leg rest
## a slope down toward the feet (`_surgical_pads`), so it reads as a tilted chair.
static func _pads(spec: FurnitureSpec, kit: MeshKit, inner: Rect2) -> void:
	var surgical := _surgical(spec)
	var pad := ObjectArtClinicConfig.recliner_vinyl_color if surgical else spec.color
	var frame_h := ObjectMeshChairConfig.recliner_frame_height
	var heights := [
		ObjectMeshChairConfig.recliner_head_height,
		ObjectMeshChairConfig.recliner_back_height,
		ObjectMeshChairConfig.recliner_seat_height,
		ObjectMeshChairConfig.recliner_leg_height,
	]
	if surgical:
		heights[0] = ObjectMeshClinicConfig.head_height
	for k in SECTIONS.size():
		var y0 := inner.position.y + roundf(inner.size.y * SECTIONS[k][0])
		var y1 := inner.position.y + roundf(inner.size.y * SECTIONS[k][1])
		var narrow := 4.0 if k == 0 else 0.0
		var rect := spec.area(
			inner.position.x + narrow, y0, inner.size.x - narrow * 2.0, y1 - y0 - 1.0
		)
		var top: float = heights[k]
		var slope := 0.0
		if surgical and k == 1:
			top = ObjectMeshChairConfig.recliner_seat_height
			slope = ObjectMeshClinicConfig.back_height - top
		elif surgical and k == 3:
			top = ObjectMeshClinicConfig.foot_height
			slope = ObjectMeshChairConfig.recliner_seat_height - top
		kit.box(MeshKit.volume(rect, frame_h, top - frame_h), MeshKit.tone(pad, &"dark"), pad)
		if slope > 0.0:
			kit.wedge(
				MeshKit.volume(rect, top, slope),
				Vector2.UP,
				pad,
				MeshKit.tone(pad, &"light"),
			)


## The surgical chair's two straps across the pads and the lamp's pole, arm and head.
static func _straps_and_lamp(spec: FurnitureSpec, kit: MeshKit, inner: Rect2) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var frame_colour := ObjectArtClinicConfig.recliner_frame_color
	var seat := ObjectMeshChairConfig.recliner_seat_height
	# one across the sloping back (halfway up it), one across the seat
	var strap_tops := {
		0.36: (seat + ObjectMeshClinicConfig.back_height) * 0.5 + 1.5, 0.62: seat + 1.5,
	}
	for f: float in strap_tops:
		var y := inner.position.y + roundf(inner.size.y * f)
		kit.box(
			MeshKit.volume(spec.area(inner.position.x, y, inner.size.x, 1.6), 0.0, strap_tops[f]),
			ObjectArtTechConfig.tech_dark_color,
		)
	var lamp_at := Vector2(w * 0.5, d * 0.42) - spec.half()
	var mount := Vector2(w - 2.0, 4.0) - spec.half()
	var top := ObjectMeshChairConfig.recliner_lamp_height
	kit.box(MeshKit.volume(Rect2(mount - Vector2.ONE, Vector2(2, 2)), 0.0, top), frame_colour)
	var square := PackedVector2Array(
		[Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	)
	spec.level(kit)
	kit.loft(
		PackedVector3Array(
			[Vector3(mount.x, top - 1.0, mount.y), Vector3(lamp_at.x, top - 1.0, lamp_at.y)]
		),
		square,
		frame_colour,
	)
	kit.cylinder(Vector3(lamp_at.x, top - 3.0, lamp_at.y), 6.0, 3.0, frame_colour)


## The glowing parts: the surgeon's lens, or the rig's halo of LEDs round the headrest.
static func _glow(spec: FurnitureSpec) -> Mesh:
	var w := spec.size.x
	var d := spec.size.y
	var kit := spec.kit()
	if _surgical(spec):
		var lamp_at := Vector2(w * 0.5, d * 0.42) - spec.half()
		var top := ObjectMeshChairConfig.recliner_lamp_height
		kit.cylinder(
			Vector3(lamp_at.x, top, lamp_at.y),
			3.0,
			0.6,
			ObjectArtClinicConfig.recliner_lamp_color,
		)
		return kit.build()
	var o := Vector2(w * 0.5, 4.0 + 5.0) - spec.half()
	var height := ObjectMeshChairConfig.recliner_head_height + 1.0
	for i in LEDS:
		var a := PI + PI * i / (LEDS - 1)
		var at := o + Vector2(cos(a), sin(a) * 0.7) * 10.0
		kit.box(
			MeshKit.volume(Rect2(at - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), height, 1.6),
			ObjectArtTechConfig.tech_led_colors[0],
		)
	return kit.build()
