class_name GrenadeMesh
extends RefCounted
## Items domain, a held grenade's 3D mesh (#193 phase 2, `domain-art/meshes.md`): a body, a cap at
## its front and the lever held down along its top, in the colours of the grenade's look
## (`GrenadeConfig.look`: shell, cap, lever), sized from its row's `art_size`. One mesh per kind and
## look, shared (`MeshCache`); the character's body places it (`GrenadeArt.held_mesh`).
##
## The frame is the gun's (`GunMesh`): the origin is the weapon hand, the front leads along +z, the
## middle of the grenade `ItemMeshConfig.grenade_ahead` ahead of the hand as the 2D art draws it.

## The cap's share of the length and of the width, the rest of the length the body's.
const CAP_LENGTH := 0.25
const CAP_WIDTH := 0.64


## The mesh of grenade `kind` (a `GrenadeConfig` row id) drawn in `look` (`GrenadeConfig.look`),
## with the lever held down unless `lever` is off (a grenade thrown has let it go).
static func of(kind: StringName, look: Dictionary, lever := true) -> Mesh:
	var row := GrenadeConfig.row(kind)
	if row.is_empty() or look.is_empty():
		return null
	var art: Vector2 = row.get("art_size", Vector2.ZERO)
	var colours := {
		"shell": look["shell"],
		"cap": look.get("cap", look["shell"]),
		"lever": look.get("lever", look["shell"]),
	}
	var opts := {
		"colours": colours,
		"thickness": ItemMeshConfig.thickness,
		"sides": ItemMeshConfig.sides,
		"ahead": ItemMeshConfig.grenade_ahead,
		"lever": [ItemMeshConfig.lever_lift, ItemMeshConfig.lever_width] if lever else [],
	}
	var key := MeshCache.key("held_grenade", art, look["shell"], opts)
	return MeshCache.fetch(key, _make.bind(art, colours, lever))


## The kit's mesh: a grenade `art` px (across, along), with its lever when `lever`.
static func _make(art: Vector2, colours: Dictionary, lever: bool) -> Mesh:
	var kit := MeshKit.new()
	kit.sides = ItemMeshConfig.sides
	var width := art.x * ItemMeshConfig.thickness
	var back := ItemMeshConfig.grenade_ahead - art.y * 0.5
	var front := back + art.y
	var cap_from := front - art.y * CAP_LENGTH
	_cylinder(kit, colours["shell"], width * 0.5, back, cap_from)
	_cylinder(kit, colours["cap"], width * 0.5 * CAP_WIDTH, cap_from, front)
	if not lever:
		return kit.build()
	var lift: float = width * ItemMeshConfig.lever_lift
	var half: float = width * ItemMeshConfig.lever_width * 0.5
	kit.box(
		AABB(
			Vector3(-half, width * 0.5, back + art.y * 0.1),
			Vector3(half * 2.0, lift, cap_from - back - art.y * 0.1),
		),
		colours["lever"],
	)
	return kit.build()


## A cylinder of `radius` px along z from `from` to `to`, about the middle height.
static func _cylinder(kit: MeshKit, color: Color, radius: float, from: float, to: float) -> void:
	kit.pose(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, from)))
	kit.cylinder(Vector3.ZERO, radius, to - from, color)
	kit.pose(Transform3D.IDENTITY)
