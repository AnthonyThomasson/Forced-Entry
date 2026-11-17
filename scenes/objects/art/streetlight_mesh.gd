extends RefCounted
## Objects domain, the 3D mesh of a street lamp (the pattern is `table_mesh.gd`,
## `domain-art/meshes.md`): the piece is a thin steel post on a base plate within its round
## footprint, anchored, as tall as anything on the street (`ObjectMeshOverheadConfig.post_height`),
## and its arm and head hang overhead out over the road, where the piece's `Overhang` draws them
## (`streetlight_painter.gd`, `part: "overhang"`: the arm from the post's top, at its end `head`
## `cobra`, a dented housing whose lens faces down at the road, or `sign`, a dark board with a neon
## tube round it and bars of letters). The lens and the sign's tube and letters are glow nodes of
## the piece's rig (the sodium lens, the sign's neon): no real light, which the Lighting domain
## gives. The arm and head are the overhang's: a piece with none is the post alone.

const Decay = preload("res://scenes/objects/art/decay.gd")
const OPTIONS := ["head", "neon", "head_px"]


## The node a streetlight `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"streetlight", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if spec.overhang.has_area():
		if _sign(spec):
			var neon := _neon(spec)
			for letters in [false, true]:
				var glow := FurnitureMesh.fetch_glow(
					"streetlight_%s" % letters,
					spec,
					tuning,
					func() -> Mesh: return _tube(spec, letters),
				)
				rig.add_glow(
					glow,
					neon.lightened(0.45 if letters else 0.15),
					ObjectMeshStateConfig.neon_strength,
				)
		else:
			var glow := FurnitureMesh.fetch_glow(
				"streetlight", spec, tuning, func() -> Mesh: return _lens(spec)
			)
			var lens := ObjectArtOutdoorConfig.streetlight_lens_color
			rig.add_glow(glow, lens, ObjectMeshStateConfig.lens_strength)
	return rig


## Whether the head is a neon sign (`art_opts.head`), else the cobra lamp.
static func _sign(spec: FurnitureSpec) -> bool:
	return String(spec.opts.get("head", ObjectArtOutdoorConfig.streetlight_head)) == "sign"


## The sign's neon: its own, else magenta.
static func _neon(spec: FurnitureSpec) -> Color:
	var own := Decay.neon(spec.opts)
	return own if own.a > 0.0 else ObjectArtLightConfig.neon_magenta


## How long the head is along the arm (px): the option, else the holder's.
static func _head_px(spec: FurnitureSpec) -> int:
	return int(spec.opts.get("head_px", ObjectArtOutdoorConfig.streetlight_head_px))


## Where the head's centre lies along the overhang's depth (px from its back edge), the painter's
## rule.
static func head_at(spec: FurnitureSpec) -> float:
	return spec.overhang.size.y - float(int(_head_px(spec) / 2.0)) - 1.0


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return {
		"opts": spec.read(OPTIONS, { "head": ObjectArtOutdoorConfig.streetlight_head }),
		"sizes": [
			ObjectMeshOverheadConfig.post_height, ObjectMeshOverheadConfig.post_radius,
			ObjectMeshOverheadConfig.arm_thickness, ObjectMeshOverheadConfig.head_height,
			ObjectMeshOverheadConfig.sign_height, ObjectMeshOverheadConfig.sign_depth,
		],
		"head_px": _head_px(spec),
		"colours": [
			ObjectArtOutdoorConfig.streetlight_plate_color,
			ObjectArtOutdoorConfig.streetlight_head_color,
			ObjectArtOutdoorConfig.streetlight_flyer_color,
			ObjectArtOutdoorConfig.streetlight_lens_color,
			ObjectArtOutdoorConfig.streetlight_sign_color,
		],
		"neon": _neon(spec),
	}


## The solids of the piece, built once per cache key: the plate, the post and the overhead part.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var plate := ObjectArtOutdoorConfig.streetlight_plate_color
	var half := floorf(minf(spec.size.x, spec.size.y) / 2.0) - 1.0
	var post := ObjectMeshOverheadConfig.post_height
	kit.cylinder(Vector3.ZERO, half, 1.5, plate)
	kit.cylinder(
		Vector3(0, 1.5, 0), ObjectMeshOverheadConfig.post_radius, post - 1.5, spec.color,
		MeshKit.tone(spec.color, &"light"),
	)
	var flyer := Vector3(0.0, post * 0.35, -ObjectMeshOverheadConfig.post_radius - 0.2)
	kit.box(
		AABB(flyer - Vector3(2.0, 0.0, 0.0), Vector3(4.0, 8.0, 0.4)),
		ObjectArtOutdoorConfig.streetlight_flyer_color,
	)
	if spec.overhang.has_area():
		_arm(spec, kit)
		if _sign(spec):
			_board(spec, kit)
		else:
			_cobra(spec, kit)
	return kit.build()


## The arm from the post's top out to just short of the head.
static func _arm(spec: FurnitureSpec, kit: MeshKit) -> void:
	var thick := ObjectMeshOverheadConfig.arm_thickness
	var run := maxf(1.0, head_at(spec) - 4.0)
	kit.box(
		AABB(
			Vector3(-thick * 0.5, ObjectMeshOverheadConfig.post_height - thick, 0.0),
			Vector3(thick, thick, run),
		),
		MeshKit.tone(ObjectArtOutdoorConfig.streetlight_head_color, &"dark"),
		ObjectArtOutdoorConfig.streetlight_head_color,
	)
	kit.cylinder(
		Vector3(0, ObjectMeshOverheadConfig.post_height - thick, 0), thick * 1.1, thick,
		MeshKit.tone(ObjectArtOutdoorConfig.streetlight_head_color, &"dark"),
	)


## The cobra head: an oval housing hung at the arm's end.
static func _cobra(spec: FurnitureSpec, kit: MeshKit) -> void:
	var rx := maxf(3.0, floorf(spec.overhang.size.x / 2.0) - 2.0)
	var at := head_at(spec)
	var housing := Rect2(-rx, at - 7.0, rx * 2.0, 15.0)
	var colour := ObjectArtOutdoorConfig.streetlight_head_color
	kit.extrude(
		FurnitureSpec.ellipse(housing, 14),
		ObjectMeshOverheadConfig.post_height - ObjectMeshOverheadConfig.head_height,
		ObjectMeshOverheadConfig.head_height,
		colour,
		MeshKit.tone(colour, &"light"),
	)


## The lens under the housing: a flat oval facing the road, the glow.
static func _lens(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	var at := head_at(spec)
	kit.extrude(
		FurnitureSpec.ellipse(Rect2(-3, at - 2.0, 6, 7), 10),
		ObjectMeshOverheadConfig.post_height - ObjectMeshOverheadConfig.head_height - 0.3,
		0.3,
		ObjectArtOutdoorConfig.streetlight_lens_color,
	)
	return kit.build()


## The sign: a dark board standing across the arm's end, as wide as the 2D art draws it.
static func _board(spec: FurnitureSpec, kit: MeshKit) -> void:
	var at := head_at(spec)
	var width := spec.overhang.size.x - 2.0
	var depth := ObjectMeshOverheadConfig.sign_depth
	var colour := ObjectArtOutdoorConfig.streetlight_sign_color
	kit.box(
		AABB(
			Vector3(
				-width * 0.5,
				ObjectMeshOverheadConfig.post_height - ObjectMeshOverheadConfig.sign_height,
				at - depth * 0.5,
			),
			Vector3(width, ObjectMeshOverheadConfig.sign_height, depth),
		),
		colour,
		MeshKit.tone(colour, &"light"),
	)


## The sign's tube round its edge (or its letters: two bars and a long one), a thin plate on both
## faces of the board.
static func _tube(spec: FurnitureSpec, letters: bool) -> Mesh:
	var kit := spec.kit()
	var at := head_at(spec)
	var width := spec.overhang.size.x - 2.0
	var height := ObjectMeshOverheadConfig.sign_height
	var depth := ObjectMeshOverheadConfig.sign_depth
	var base := ObjectMeshOverheadConfig.post_height - height
	var rows: Array[Rect2] = []
	if letters:
		var scale := height / 12.0
		rows = [
			Rect2(
				5.0 - spec.overhang.size.x * 0.5,
				5.0 * scale,
				spec.overhang.size.x * 0.42 - 5.0,
				1.2,
			),
			Rect2(spec.overhang.size.x * 0.04, 5.0 * scale, spec.overhang.size.x * 0.46 - 6.0, 1.2),
			Rect2(7.0 - spec.overhang.size.x * 0.5, 2.5 * scale, spec.overhang.size.x - 15.0, 1.2),
		]
	else:
		var inner := Rect2(-width * 0.5 + 1.0, 1.0, width - 2.0, height - 2.0)
		rows = [
			Rect2(inner.position.x, 1.0, inner.size.x, 1.0),
			Rect2(inner.position.x, height - 2.0, inner.size.x, 1.0),
			Rect2(inner.position.x, 1.0, 1.0, inner.size.y),
			Rect2(inner.end.x - 1.0, 1.0, 1.0, inner.size.y),
		]
	for face: float in [depth * 0.5, -depth * 0.5 - 0.4]:
		for row in rows:
			kit.box(
				AABB(
					Vector3(row.position.x, base + row.position.y, at + face),
					Vector3(row.size.x, row.size.y, 0.4),
				),
				_neon(spec),
			)
	return kit.build()
