class_name GunMesh
extends RefCounted
## Items domain, a held gun's 3D mesh (#193 phase 2, `domain-art/meshes.md`): low-poly solids of
## Art's mesh kit in the colours of the gun's look (`GunConfig.look`: body, stock, guard, grip,
## barrel, magazine), sized from its row (`art_size` across and along, `grip_back`) and chunked by
## `ItemMeshConfig.thickness`. One mesh per gun and look, shared by every character holding it
## (`MeshCache`); the character's body places it (`GunArt.held_mesh`, `domain-character`).
##
## The frame is the one the 2D art is drawn in, turned to 3D: the origin is the weapon hand's grip
## and the muzzle leads along +z (2D "ahead"), the butt `grip_back` behind the origin, up is +y.
## A long gun (`raises_at_contact`) is a stock, a receiver, a hand guard, a barrel, a magazine and a
## grip; a pistol is a slide over a grip with its frame. A shape is a share of the gun's length
## and width, so a row with other sizes is built from the same recipe.

## Where along the length (share, from the butt) each long-gun part ends: the stock, the receiver,
## the hand guard (the barrel runs on to the muzzle).
const STOCK_END := 0.28
const RECEIVER_END := 0.62
const GUARD_END := 0.84
## The same for a pistol's grip and its frame under the slide, and how much of the muzzle end is
## the barrel's colour.
const PISTOL_GRIP_END := 0.38
const PISTOL_FRAME_END := 0.75
const PISTOL_MUZZLE := 0.15


## The mesh of `gun` (a `GunConfig` row id) drawn in `look` (`GunConfig.look`), cached by the row's
## sizes, the look's colours and the tuning.
static func of(gun: StringName, look: Dictionary) -> Mesh:
	var row := GunConfig.row(gun)
	if row.is_empty() or look.is_empty():
		return null
	var art: Vector2 = row.get("art_size", Vector2.ZERO)
	var grip := float(row.get("grip_back", 0.0))
	var long: bool = row.get("raises_at_contact", false)
	var colours := {}
	for part in ["body", "stock", "guard", "grip", "barrel", "magazine"]:
		colours[part] = look.get(part, look["body"])
	var opts := {
		"grip": grip,
		"long": long,
		"colours": colours,
		"thickness": ItemMeshConfig.thickness,
		"sides": ItemMeshConfig.sides,
	}
	var key := MeshCache.key("held_gun", art, look["body"], opts)
	return MeshCache.fetch(key, _make.bind(art, grip, long, colours))


## The kit's mesh: a gun `art` px (across, along) with its butt `grip` behind the origin.
static func _make(art: Vector2, grip: float, long: bool, colours: Dictionary) -> Mesh:
	var kit := MeshKit.new()
	kit.sides = ItemMeshConfig.sides
	var width := art.x * ItemMeshConfig.thickness
	var butt := -grip
	var length := art.y
	if long:
		_long_gun(kit, colours, width, butt, length)
	else:
		_pistol(kit, colours, width, butt, length)
	return kit.build()


## A stock, a receiver with a grip and a magazine under it, a hand guard and a barrel, from `butt`
## (z) `length` along, `width` across.
static func _long_gun(
	kit: MeshKit,
	colours: Dictionary,
	width: float,
	butt: float,
	length: float,
) -> void:
	var stock := butt + length * STOCK_END
	var receiver := butt + length * RECEIVER_END
	var guard := butt + length * GUARD_END
	_block(kit, colours["stock"], width * 0.36, Vector2(-0.5, 0.95) * width, Vector2(butt, stock))
	_block(
		kit, colours["body"], width * 0.5, Vector2(-0.25, 1.05) * width, Vector2(stock, receiver)
	)
	_block(
		kit, colours["guard"], width * 0.42, Vector2(0.0, 0.85) * width, Vector2(receiver, guard)
	)
	_block(
		kit,
		colours["grip"],
		width * 0.28,
		Vector2(-0.95, -0.25) * width,
		Vector2(stock, stock + length * 0.1),
	)
	_block(
		kit,
		colours["magazine"],
		width * 0.26,
		Vector2(-1.15, -0.25) * width,
		Vector2(butt + length * 0.4, butt + length * 0.5),
	)
	_barrel(
		kit,
		colours["barrel"],
		Vector2(width * 0.2, width * 0.5),
		Vector2(guard, butt + length),
	)


## A slide over a frame and a grip, its muzzle end in the barrel's colour.
static func _pistol(
	kit: MeshKit,
	colours: Dictionary,
	width: float,
	butt: float,
	length: float,
) -> void:
	var muzzle := butt + length
	_block(kit, colours["body"], width * 0.42, Vector2(0.1, 0.95) * width, Vector2(butt, muzzle))
	_block(
		kit,
		colours["barrel"],
		width * 0.3,
		Vector2(0.2, 0.85) * width,
		Vector2(muzzle - length * PISTOL_MUZZLE, muzzle),
	)
	_block(
		kit,
		colours["guard"],
		width * 0.3,
		Vector2(-0.1, 0.15) * width,
		Vector2(butt + length * 0.3, butt + length * PISTOL_FRAME_END),
	)
	_block(
		kit,
		colours["grip"],
		width * 0.36,
		Vector2(-1.2, 0.1) * width,
		Vector2(butt, butt + length * PISTOL_GRIP_END),
	)


## A box `half` px each side of the middle, from height `y.x` to `y.y` and from `span.x` to `span.y`
## along z.
static func _block(kit: MeshKit, color: Color, half: float, y: Vector2, span: Vector2) -> void:
	var size := Vector3(half * 2.0, y.y - y.x, span.y - span.x)
	kit.box(AABB(Vector3(-half, y.x, span.x), size), color)


## A round barrel (`bore`: its radius and its height) from `span.x` to `span.y` along z: an upright
## cylinder laid down about the x axis.
static func _barrel(kit: MeshKit, color: Color, bore: Vector2, span: Vector2) -> void:
	kit.pose(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, bore.y, span.x)))
	kit.cylinder(Vector3.ZERO, bore.x, span.y - span.x, color)
	kit.pose(Transform3D.IDENTITY)
