class_name BodyMesh
extends Node3D
## Character body, the 3D mesh of a living character (`domain-art/meshes.md`): a
## low-poly, upright, human-proportioned body of the mesh kit's solids (`BodySolids`) that the 3D
## mirror shows in place of the character's proxy capsule. A trunk (the shirt, over it a vest, its
## plates and a pack), a head (skin, hair or a cap or helmet, a visor band across the front of the
## face), two arms, two hands and two legs with their shoes (a boot's shaft over the shin), each in
## the colour the 2D painters draw it in (`BodyDress`: the style, the outfit and the plates'
## colours).
##
## **Where the parts are** is the 2D body's own rig (`anatomy.rig()`, `character_rig.gd`): the same
## joints the painters draw the limbs between, solved once per physics frame and shared. They turn
## with the character's pose (not its node, which is never rotated), so the body faces where the 2D
## one does, the arms hold what the hands hold, the legs stride as the gait says and a crouch folds
## the spine and lowers the hips as `CharacterPostureConfig` says (docs/cover-and-stance.md P3). The
## rig's heights are the drawing's (a head 100 px up); the mesh squeezes them so the head stands
## `CharacterMeshConfig.height` high, and the horizontal reach is unchanged (a knee's and an elbow's
## bend shrinks with the squeeze, `_bend_joint`).
## **How it follows:** the parts are shared unit solids (`BodySolids`: a trunk, a head, tapered
## limbs, a neck, a shoe, a ball, a box; `MeshCache`), all drawn as ONE mesh (`PartSkin`, Art:
## `part(index)` reads one), scaled and placed between the rig's joints by
## `mirror_update(body)` (the mirror calls
## it each frame the mesh shows), only when a joint moved; a new look (an outfit, a style) only
## re-tints and shows or hides the optional parts and joins the mesh again (`_dress_parts`).
## **What it holds** is one more node, `held()`: the mesh the held item's art gives
## (`item.art.held_mesh()`, Items: from the item's config row, shared by kind and look), placed at
## the weapon hand's joint, pointing where the 2D art draws the weapon and pitched up as it is
## raised off a wall; it swaps with the held slot and shows nothing for a fist or an empty hand
## (`BodyHeld`). A seated body's hides with its shapes (the mirror's).
## **Once dead** (`on_body_died` answers true) the body follows the 2D ragdoll's joints
## (`anatomy.ragdoll`, the same indices and reads as the rig), flat on the floor, written only as a
## joint moves and not at all once the ragdoll has settled; the held item is gone (the 2D drops a
## gun as a `DroppedItem`, a grenade is not drawn on a fallen body).

const Rig = preload("res://scenes/character/body/character_rig.gd")
const Fallen = preload("res://scenes/character/body/character_ragdoll.gd")
## The parts, of the skin: the trunk's and the head's, then the sided ones (two each, side 0 first).
const TORSO := 0
const VEST := 1
const PLATE := 2
const PACK := 4
const HEAD := 5
const HAIR := 6
const HEADWEAR := 7
const FACE := 8
const UPPER := 9
const FORE := 11
const HAND := 13
const THIGH := 15
const SHIN := 17
const BOOT := 19
const FOOT := 21
const NECK := 23
## The head's art laid flat over the crown (a cut-out sprite: the whole canvas, the brim and the ear
## pods the dome's disc cannot carry).
const CROWN := 24
## The shape each part is made of (`_solid`), by the indices above.
const SHAPES := [
	&"trunk", &"vest", &"box", &"box", &"box", &"head", &"ball", &"ball", &"box",
	&"upper", &"upper", &"fore", &"fore", &"ball", &"ball", &"thigh", &"thigh", &"shin",
	&"shin", &"boot", &"boot", &"shoe", &"shoe", &"neck", &"box",
]
## How far above the highest dome the head's sprite lies (px), and its thickness (px).
const CROWN_LIFT := 1.0
const CROWN_THICK := 0.5
## The joints and the flat directions the pose is made from, in one array to compare a frame's with
## the last: the rig's seventeen joints, the two feet's toes and the face, and what the held item
## points along (flat x, y) and how far it is pitched up (z).
const JOINTS := 17
const SAMPLE := 23
## How far a joint (px) or a flat direction (its length, about 1 degree for 0.02) must move from the
## pose the parts are in to pose them again: a body at rest, its breath and its head's spring still
## settling, is not re-placed every frame. A joint's is under one pixel of the 3D picture.
const MOVED := 0.2
const TURNED := 0.02
## How far down the shin (0 knee .. 1 ankle) a boot's shaft starts, and how much wider than the
## shin it is.
const BOOT_TOP := 0.62
const BOOT_GROW := 1.05
## How far round its origin (px) all a standing body draws stays: its parts, the held item and the
## drop shadow.
const REACH := 160.0
## How far past the joints a posed part can reach (body radii): what the body is culled by.
const PARTS_REACH := 1.5
## A shoe's length over the 2D art's foot (`CharacterBodyConfig.foot`): a shoe is about a head long.
const SHOE_LENGTH := 0.8
## How many physics frames a fallen body's joints take to rise to their clearance over the floor.
const LIE_FRAMES := 18
## The held item's sample: its index among the joints.
const AIM := JOINTS + 3
## The fists' own sample: the way each one faces (a flat direction), after the held item's.
const FISTS := JOINTS + 4
## How a limb's top (the face its art lies on) is chosen: up, but for a limb steeper than this
## (the height of its unit direction, from where to where) it turns toward the face, so a hanging
## arm's strip lies on its front.
const STEEP := Vector2(0.6, 0.95)
## The neck's width at the head over its width at the shoulders, and how far below the chest joint
## it starts (body radii).
const NECK_TAPER := 0.9
const NECK_SINK := 0.1
## The head's parts over its radius: the hair (size, how far up and back), a cap's and a helmet's,
## the face band's size (width across, height, depth) and how far forward its middle sits, all over
## the head's radius, and the band's own height above the head's middle.
const HAIR_SHAPE := Vector3(1.06, 0.2, 0.2)
const CAP_SHAPE := Vector3(1.12, 0.3, 0.25)
const HELMET_SHAPE := Vector3(1.22, 0.15, 0.3)
const FACE_SHAPE := Vector3(0.9, 0.34, 0.5)
const FACE_FORWARD := 0.85
const FACE_BASE := -0.1
## Where along the trunk a plate sits (its length up from the pelvis).
const PLATE_AT := 0.55
## How deep into the vest's back the pack sits (a share of the vest's depth there).
const PACK_SET := 0.85

## The body's radius, its dress, the hands' size and the head's.
var _r := 14.0
var _dress: BodyDress
var _hand_radius := 4.0
var _head_radius := 5.0
## How the rig's heights are squeezed (`CharacterMeshConfig.height`).
var _squeeze := 1.0
## The physics frame last posed, the joints it was posed from (sized once, copied into: no array
## is made per frame) and whether `_last` holds a pose the parts are in.
var _frame := -1
var _last := PackedVector3Array()
var _sample := PackedVector3Array()
var _posed := false
## The parts, drawn as one mesh (the first child): `_skin.parts`, by the indices above (a sided
## part's own is its index plus the side).
var _skin: PartSkin
## What is read once a dressing or a pose and used by many parts.
var _read := Read.new()
## The drop shadow (the child after the held item's: `_make_shade`).
var _shade: MeshInstance3D
## What the character holds (`BodyHeld`: its node is the child after the parts' mesh).
var _held := BodyHeld.new()
## The physics frame the body died in (-1 while it lives: it follows the ragdoll from then), and
## whether it was posed at rest (the ragdoll asleep).
var _died := -1
var _at_rest := false


## The part at `index` (the constants above): where it is posed, what it wears, whether it shows.
func part(index: int) -> MeshPart:
	return _skin.parts[index]


## The body of `body` (a character with an anatomy and a wardrobe), or null for a node that is
## none: the carrier then makes none. The body keeps its own `BodyDress` (the look its
## wardrobe resolves).
static func build(body: Node2D) -> Node3D:
	if not body.is_in_group(&"characters") or body.get("anatomy") == null:
		return null
	if not body.get("wardrobe") is CharacterWardrobe:
		return null
	var mesh := BodyMesh.new()
	var dress := BodyDress.new()
	dress.refresh(body.wardrobe)
	mesh._make(body, dress)
	return mesh


## The look this body is dressed in (what its wardrobe resolved at the last update).
func look_worn() -> BodyDress:
	return _dress


## The sphere (3D units) round its origin all the body draws stays in while it lives, so the mirror
## does not pose it off the camera; a fallen body's joints are the ragdoll's, wherever they are
## flung: always posed.
func mirror_reach() -> float:
	return INF if _died >= 0 else REACH * RenderConfig.unit


## Place the parts between the joints the rig holds now, once for each physics frame and only when a
## joint moved, and dress them again when the look changed.
func mirror_update(body: Node2D) -> void:
	if _died < 0:
		# The call is cheap and answers at once when nothing changed.
		_dress.refresh(body.wardrobe)
		if _dress.look_key != _read.look_key:
			_dress_parts()
			_frame = -1  # a new look may resize parts (a cap for a helmet) even with no joint moved
			_posed = false  # and a part it shows has not been placed while it was hidden
	var frame := Engine.get_physics_frames()
	if frame == _frame:
		return
	_frame = frame
	if _died < 0:
		_pose(body.anatomy.rig(), body)
		return
	var ragdoll: Fallen = body.anatomy.ragdoll
	if _at_rest and ragdoll.is_settled():
		return  # a settled body costs nothing more until a blast wakes it
	# At rest only once the clearance has eased in fully, whatever the tick rate.
	_at_rest = ragdoll.is_settled() and frame - _died >= LIE_FRAMES
	_pose(ragdoll, body)


## The body died: it keeps following, now the 2D ragdoll's joints, unless the ragdoll is not there
## (then the carrier hides it). Its look is resolved once more first: the killing blow wears a plate
## after the last update. A body on the floor keeps its drop shadow (it lies along the body,
## `_pose_shade`), and the held item goes with the hand that held it.
func on_body_died(body: Node2D) -> bool:
	if not body.anatomy.ragdoll is Fallen:
		return false
	_dress.refresh(body.wardrobe)
	if _dress.look_key != _read.look_key:
		_dress_parts()
	_died = Engine.get_physics_frames()
	_at_rest = false
	_posed = false
	_frame = -1
	return true


## The drop shadow: a patch under the body, shifted away from the art's light, which the body's
## parts (they cast nothing from the lights) leave to be its shadow.
func _make_shade() -> void:
	var radius := _r * CharacterShadowConfig.shade_radius
	_shade = MeshNodes.shade(
		radius, ArtCanvasConfig.drop_shadow_alpha, CharacterShadowConfig.shade_lift
	)
	var away := -ArtCanvasConfig.light_from.normalized() * _r * CharacterShadowConfig.shade_shift
	_shade.position += Vector3(away.x, 0.0, away.y) * RenderConfig.unit
	_shade.name = "DropShadow"
	add_child(_shade)


## The drop shadow under the posed body: a disc under a body that stands or crouches, and one that
## lies (a fallen body, a lying one: head and feet apart on the floor) is a patch stretched along it
## from head to feet, `shade_width` radii across. Shifted
## away from the art's light as the standing one is.
func _pose_shade() -> void:
	var head := _flat(_last[Rig.HEAD])
	var feet := (_flat(_last[Rig.ANKLE[0]]) + _flat(_last[Rig.ANKLE[1]])) * 0.5
	var along := head - feet
	var disc := _r * CharacterShadowConfig.shade_radius
	var away := -ArtCanvasConfig.light_from.normalized() * _r * CharacterShadowConfig.shade_shift
	var stretch := Vector2.ONE
	var middle := Vector2.ZERO
	var angle := 0.0
	if along.length() > _r * CharacterShadowConfig.shade_lies:
		middle = (head + feet) * 0.5
		stretch = Vector2(
			(along.length() * 0.5 + _r) / disc, _r * CharacterShadowConfig.shade_width / disc
		)
		angle = atan2(-along.y, along.x)
	var at := middle + away
	_shade.position = Vector3(at.x, CharacterShadowConfig.shade_lift, at.y) * RenderConfig.unit
	_shade.basis = Basis(Vector3.UP, angle) * Basis.from_scale(Vector3(stretch.x, 1.0, stretch.y))


## A joint of the rig (3D units: x, height, y) as its flat place in px.
static func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) / RenderConfig.unit


## The node showing what the character holds, hidden while nothing is (the held slot's item has no
## mesh: fists, an empty hand, a key), or the body is dead.
func held() -> MeshInstance3D:
	return _held.node


## Make the parts of `body`, dressed in `dress`, and pose them.
func _make(body: Node2D, dress: BodyDress) -> void:
	_dress = dress
	_r = body.radius
	var hands: Node = body.get_node_or_null("Hands")
	if hands != null and hands.get("hand_radius") is float:
		_hand_radius = hands.get("hand_radius")
	_head_radius = CharacterArtConfig.head_size * 2.0 * _r * CharacterMeshConfig.head_scale
	_squeeze = Rig.squeeze(_r)
	_sample.resize(SAMPLE)
	_last.resize(SAMPLE)
	assert(SHAPES.size() == CROWN + 1, "BodyMesh: the shapes list and the part indices disagree")
	_skin = PartSkin.new(SHAPES.size())
	for i in SHAPES.size():
		_skin.parts[i].mesh = _solid(SHAPES[i], Color.WHITE)
	MeshNodes.figure(_skin.node)
	add_child(_skin.node)
	add_child(_held.node)
	_make_shade()
	_dress_parts()
	_pose(body.anatomy.rig(), body)


## The shared solid `shape` (`BodySolids`: one mesh for every body of its `color`) a part is made
## of. The limbs take the 2D art's widths (`CharacterArtConfig.body_arm_widths`, ...), tapering as
## the drawn limbs do; the vest is the trunk's own shape from `CharacterMeshConfig.vest_from` up.
static func _solid(shape: StringName, color: Color) -> Mesh:
	var arm := CharacterArtConfig.body_arm_widths
	var leg := CharacterArtConfig.body_leg_widths
	var radii := []
	match shape:
		&"vest":
			return BodySolids.fetch(&"trunk", { "from": CharacterMeshConfig.vest_from }, color)
		&"upper":
			radii = [Vector2(0, arm[0]), Vector2(1, arm[1])]
		&"fore":
			radii = [Vector2(0, arm[1]), Vector2(1, arm[2])]
		&"thigh":
			radii = [Vector2(0, leg[0]), Vector2(1, leg[1])]
		&"shin":
			radii = [Vector2(0, leg[1]), Vector2(0.3, leg[2]), Vector2(1, leg[3])]
		&"boot":
			radii = [Vector2(0, 1), Vector2(1, 1)]
		&"neck":
			radii = [Vector2(0, 1), Vector2(1, NECK_TAPER)]
	if radii.is_empty():
		return BodySolids.fetch(shape, {}, color)
	return BodySolids.fetch(&"limb", BodySolids.limb(radii), color)


## Colour the parts from the look the dress resolved, and show the optional ones it asks for: the
## vest and its plates, a pack, hair or a cap or helmet, a boot's shaft.
func _dress_parts() -> void:
	_read.look_key = _dress.look_key
	var look := _look()
	var skin := _dress.skin
	_coat(TORSO, _dress.shirt)
	var vest := String(look.get("vest", "")) != ""
	_coat(VEST, _colour(look.get("vest_col")))
	_skin.parts[VEST].visible = vest
	for i in 2:
		var plate: Variant = _dress.shoulder_opts.get("front_plate" if i == 0 else "back_plate")
		_skin.parts[PLATE + i].visible = vest and plate is Color
		_skin.parts[PLATE + i].tint = _colour(plate)
	_coat(PACK, _colour(look.get("pack_col")))
	_skin.parts[PACK].visible = bool(look.get("pack", false))
	_coat(HEAD, skin)
	_skin.parts[NECK].tint = skin
	_skin.parts[FACE].tint = _band_colour(skin)
	var worn := String(look.get("head", ""))
	var covered := worn == "helmet" or worn == "cap"
	_skin.parts[HEADWEAR].visible = covered
	_coat(HEADWEAR, _colour(look.get("helm")))
	_skin.parts[HAIR].visible = not covered and String(look.get("hair_style", "short")) != "bald"
	_coat(HAIR, _colour(look.get("hair")))
	for i in 2:
		_coat(UPPER + i, _colour(_dress.arm_parts[i]["upper"]["color"]))
		_coat(FORE + i, _colour(_dress.arm_parts[i]["fore"]["color"]))
		_coat(HAND + i, _colour(_dress.hand_parts[i]["color"]))
		_coat(THIGH + i, _dress.pants)
		_coat(SHIN + i, _dress.shin_colour(i))
		_skin.parts[BOOT + i].visible = _dress.boots
		_coat(BOOT + i, _dress.shoes)
		_coat(FOOT + i, _dress.shoes)
	_read.cap = worn == "cap"
	_read.top = _crown_top()
	BodyTextures.apply(_skin.parts, _dress, _r, _hand_radius)
	_skin.dress()


## Place every part between the joints of `rig` (the standing skeleton, or a ragdoll: the same
## indices and reads), unless none moved since the last time. `body` is the character, whose held
## item rides on the hand.
func _pose(rig: Object, body: Node2D) -> void:
	if _died < 0:
		_sample_standing(rig as Rig)
	else:  # a fallen body's joints are the ragdoll's own, held over the floor
		var clear := _floor_clearance()
		for i in JOINTS:
			_sample[i] = _lift(rig.point(i), clear)
	for i in 2:
		_sample[JOINTS + i] = _dir(rig.toes(i))
	_sample[JOINTS + 2] = _dir(rig.face())
	_sample[AIM] = _held.sample(body, _died >= 0)
	_sample_fists(rig, body)
	if _held.swapped:
		_held.swapped = false
		_posed = false  # a new item has not been placed
	if _posed and _unmoved():
		return
	_posed = true
	for i in SAMPLE:
		_last[i] = _sample[i]
	var face := Vector3(_last[JOINTS + 2].x, 0.0, _last[JOINTS + 2].z)
	_read.toward = face.normalized() if face.length_squared() > 0.000001 else Vector3.BACK
	_pose_trunk()
	_pose_head()
	for i in 2:
		_pose_limbs(i)
	_skin.pose()
	_skin.node.custom_aabb = _bounds()
	_pose_shade()
	_held.place(_last[AIM], _last[Rig.HAND[_held.hand]])


## A box (3D units) every posed part is in: round the joints, by `PARTS_REACH` radii.
func _bounds() -> AABB:
	var box := AABB(_last[0], Vector3.ZERO)
	for i in range(1, JOINTS):
		box = box.expand(_last[i])
	box = box.grow(_r * PARTS_REACH)
	return AABB(box.position * RenderConfig.unit, box.size * RenderConfig.unit)


## Whether every joint of `_sample` is within `MOVED`, and every direction within `TURNED`, of the
## pose the parts are in.
func _unmoved() -> bool:
	for i in SAMPLE:
		var step := MOVED if i < JOINTS else TURNED
		if _sample[i].distance_squared_to(_last[i]) > step * step:
			return false
	return true


## The trunk from the pelvis up the spine to the neck, with its vest, plates and pack, and the neck
## up to the head.
func _pose_trunk() -> void:
	var pelvis := _last[Rig.PELVIS]
	var up := _last[Rig.CHEST] - pelvis
	var frame := _frame_of(up, _last[Rig.BELLY] - _last[Rig.SPINE])
	var half := trunk_half(_r)
	var length := up.length() + CharacterMeshConfig.torso_overshoot * _r
	_place(_skin.parts[TORSO], frame, Vector3(half.x, length, half.y), pelvis)
	_pose_vest(frame, pelvis, length, half)
	_pose_pack(frame, pelvis, length, half)
	var neck := _r * 0.5 * CharacterMeshConfig.limb_scale * CharacterArtConfig.body_neck_width
	var chest := _last[Rig.CHEST]
	var base := chest - (_last[Rig.HEAD] - chest).normalized() * NECK_SINK * _r
	_segment(_skin.parts[NECK], base, _last[Rig.HEAD], neck)


## The trunk's half width and half depth (px) of a body of radius `r`.
static func trunk_half(r: float) -> Vector2:
	return Vector2(
		CharacterMeshConfig.torso_width,
		CharacterArtConfig.shoulder_depth * CharacterMeshConfig.torso_depth,
	) * r


## How thick a limb is (the px a unit of its solid's radius is) on a body of radius `r`.
static func limb_thick(r: float) -> float:
	return r * 0.5 * CharacterMeshConfig.limb_scale


## A boot's shaft's radius (px): a bit over the shin's mean width.
static func boot_radius(r: float) -> float:
	var legs := CharacterArtConfig.body_leg_widths
	return (legs[1] + legs[2] + legs[3]) / 3.0 * limb_thick(r) * BOOT_GROW


## The vest over the trunk (`frame` from `pelvis`, `length` long, `half` its half width and depth),
## and a plate on its front and back.
func _pose_vest(frame: Basis, pelvis: Vector3, length: float, half: Vector2) -> void:
	var grow := CharacterMeshConfig.vest_grow
	var from := length * CharacterMeshConfig.vest_from
	_place(
		_skin.parts[VEST],
		frame,
		Vector3(half.x * grow, length - from, half.y * grow),
		pelvis + frame.y * from,
	)
	var plate := CharacterMeshConfig.plate_size * _r
	var thick := CharacterMeshConfig.plate_thickness
	var at := length * PLATE_AT
	var shell := half.y * grow * BodySolids.trunk_width(PLATE_AT) + thick * 0.5
	for i in 2:
		_place(
			_skin.parts[PLATE + i],
			frame,
			Vector3(plate.x, plate.y, thick),
			pelvis + frame.y * at + frame.z * (shell if i == 0 else -shell),
		)


## The pack behind the trunk (arguments as `_pose_vest`).
func _pose_pack(frame: Basis, pelvis: Vector3, length: float, half: Vector2) -> void:
	var pack := Vector3(
		half.x * CharacterMeshConfig.pack_width * 2.0,
		length * CharacterMeshConfig.pack_height,
		CharacterMeshConfig.pack_depth,
	)
	var behind := half.y * CharacterMeshConfig.vest_grow * PACK_SET + pack.z * 0.5
	_place(_skin.parts[PACK], frame, pack, pelvis + frame.y * length * 0.2 - frame.z * behind)


## The head on its joint, its hair or headwear toward the back and its face band where the face
## looks.
func _pose_head() -> void:
	var at := _last[Rig.HEAD]
	# A living head is upright on its neck; a fallen one lies as its neck does.
	var up := _last[Rig.HEAD] - _last[Rig.CHEST] if _died >= 0 else Vector3.UP
	var frame := _frame_of(up, _last[JOINTS + 2])
	var r := _head_radius
	_place(_skin.parts[HEAD], frame, Vector3(r, r, r), at)
	_cover(_skin.parts[HAIR], frame, HAIR_SHAPE, at)
	_cover(_skin.parts[HEADWEAR], frame, CAP_SHAPE if _read.cap else HELMET_SHAPE, at)
	_place(
		_skin.parts[FACE],
		frame,
		FACE_SHAPE * r,
		at + frame.z * r * FACE_FORWARD + frame.y * r * FACE_BASE,
	)
	_pose_crown(frame, at)


## The head's sprite flat over the crown, turned with the head's facing: its own up is the world's
## (a living head is upright; a fallen one lies, its sprite still flat over it).
func _pose_crown(frame: Basis, at: Vector3) -> void:
	var r := _head_radius
	var flat := frame if _died < 0 else _frame_of(Vector3.UP, frame.z)
	var top := 1.0 if _died >= 0 else _read.top
	var side := BodyTextures.head_side(_r) * CharacterMeshConfig.head_scale
	_place(
		_skin.parts[CROWN],
		flat,
		Vector3(side, CROWN_THICK, side),
		at + Vector3.UP * (r * top + CROWN_LIFT),
	)


## How high the highest visible dome of the head reaches over its centre, in head radii.
func _crown_top() -> float:
	var top := (BodySolids.HEAD[BodySolids.HEAD.size() - 1] as Vector2).y
	if _skin.parts[HEADWEAR].visible:
		var shape := CAP_SHAPE if _read.cap else HELMET_SHAPE
		top = maxf(top, shape.y + shape.x * 0.85)
	if _skin.parts[HAIR].visible:
		top = maxf(top, HAIR_SHAPE.y + HAIR_SHAPE.x * 0.85)
	return top


## `node` (a ball part) over the head at `at`: `shape` is its size over the head's, how far up and
## how far back it sits.
func _cover(node: MeshPart, frame: Basis, shape: Vector3, at: Vector3) -> void:
	var r := _head_radius
	_place(
		node,
		frame,
		Vector3(shape.x, shape.x * 0.85, shape.x) * r,
		at + frame.y * r * shape.y - frame.z * r * shape.z,
	)


## Side `i`'s arm (shoulder, elbow, hand) and leg (hip, knee, ankle, with its boot and foot).
func _pose_limbs(i: int) -> void:
	var thick := _r * 0.5 * CharacterMeshConfig.limb_scale
	var elbow := _last[Rig.ELBOW[i]]
	var hand := _last[Rig.HAND[i]]
	_segment(_skin.parts[UPPER + i], _last[Rig.SHOULDER[i]], elbow, thick)
	_segment(_skin.parts[FORE + i], elbow, hand, thick)
	_place(
		_skin.parts[HAND + i],
		_frame_of(Vector3.UP, _last[FISTS + i]),
		Vector3.ONE * _hand_radius,
		hand,
	)
	_pose_leg(i, thick)


## Side `i`'s leg, its limbs `thick` px across the widths: the thigh, the shin (and a boot's shaft
## over it) and the shoe under the ankle, pointing where the toes do.
func _pose_leg(i: int, thick: float) -> void:
	var legs := CharacterArtConfig.body_leg_widths
	var knee := _last[Rig.KNEE[i]]
	var ankle := _last[Rig.ANKLE[i]]
	var shin: float = (legs[1] + legs[2] + legs[3]) / 3.0 * thick
	_segment(_skin.parts[THIGH + i], _last[Rig.HIP[i]], knee, thick)
	_segment(_skin.parts[SHIN + i], knee, ankle, thick)
	_segment(_skin.parts[BOOT + i], knee.lerp(ankle, BOOT_TOP), ankle, shin * BOOT_GROW)
	var shoes := CharacterArtConfig.body_shoe_widths
	var size := Vector3(
		(shoes[0] + shoes[1]) * 0.5 * _r,
		CharacterMeshConfig.foot_height * _r,
		CharacterBodyConfig.foot * _r * SHOE_LENGTH,
	)
	var frame := _frame_of(Vector3.UP, _last[JOINTS + i])
	var at := Vector3(ankle.x, maxf(ankle.y - size.y * 0.5, 0.0), ankle.z)
	_place(_skin.parts[FOOT + i], frame, size, at + frame.z * size.z * 0.25)


## `node` (a limb part, its solid lying along its z) laid from `from` to `to`, `radius` px across.
func _segment(node: MeshPart, from: Vector3, to: Vector3, radius: float) -> void:
	var along := to - from
	_place(
		node,
		_limb_frame(along),
		Vector3(radius, radius, maxf(along.length(), 0.01)),
		from,
	)


## The frame of a limb along `along`: its z along it, its y (the top its art lies on) up, or toward
## the way the body faces for a steep limb, so a hanging arm's strip lies on its front; x is y cross
## z (the art's across, right of the body as it faces), as everywhere.
func _limb_frame(along: Vector3) -> Basis:
	var z := along.normalized() if along.length_squared() > 0.000001 else Vector3.DOWN
	var hint := Vector3.UP.lerp(_read.toward, smoothstep(STEEP.x, STEEP.y, absf(z.y)))
	var y := hint - z * hint.dot(z)
	if y.length_squared() < 0.000001:
		y = z.cross(Vector3.RIGHT)
	y = y.normalized()
	return Basis(y.cross(z), y, z)


## `node` turned to `frame`, `size` px along its three axes, its origin at `at` px; a part not shown
## is left where it is (the look that shows it poses again).
func _place(node: MeshPart, frame: Basis, size: Vector3, at: Vector3) -> void:
	if not node.visible:
		return
	node.transform = Transform3D(
		Basis(frame.x * size.x, frame.y * size.y, frame.z * size.z),
		at * RenderConfig.unit,
	)


## The unit frame whose up is `up`, its z the `out` hint's part across it (any across when the hint
## lies along it); x is up cross z, so the frame is right-handed.
static func _frame_of(up: Vector3, out: Vector3) -> Basis:
	var y := up.normalized() if up.length_squared() > 0.000001 else Vector3.UP
	var z := out - y * out.dot(y)
	if z.length_squared() < 0.000001:
		z = y.cross(Vector3.RIGHT)
		if z.length_squared() < 0.000001:
			z = y.cross(Vector3.FORWARD)
	z = z.normalized()
	return Basis(y.cross(z), y, z)


## A rig point (local x, y, height in px) as the 3D px point: 2D `(x, y)` is `(x, height, y)`, the
## height squeezed (but a lying body's low joints are held up by `CharacterMeshConfig.lying_clear`,
## so its limbs rest on the floor, not in it).
func _lift(point: Vector3, clear: float) -> Vector3:
	return Vector3(point.x, maxf(point.z * _squeeze, clear), point.y)


## The standing body's joints from `rig`, each lifted as `_lift` does, the knees and elbows then
## bent in proportion (`_bend_joint`).
func _sample_standing(rig: Rig) -> void:
	var joints := rig.joints()
	var squeeze_by := _squeeze
	for i in JOINTS:
		var point := joints[i]
		_sample[i] = Vector3(point.x, maxf(point.z * squeeze_by, 0.0), point.y)
	for i in 2:
		_bend_joint(joints, Rig.HIP[i], Rig.KNEE[i], Rig.ANKLE[i])
		_bend_joint(joints, Rig.SHOULDER[i], Rig.ELBOW[i], Rig.HAND[i])


## The middle joint `mid` of a two-bone limb between `from` and `to` (a knee between hip and ankle,
## an elbow between shoulder and hand), lifted with its ends but bent in proportion: the rig bent it
## for the drawing's heights, and squeezing only the ends would leave it bent as far over a shorter
## chord (a standing leg with its knees thrust forward). Its place along the chord and its bend
## (the part of its offset across the chord) both shrink with the chord. `_sample` holds the three
## lifted; a chord too short to bend leaves the middle one so.
func _bend_joint(joints: Array[Vector3], from: int, mid: int, to: int) -> void:
	var a := joints[from]
	var low := _sample[from]
	var squeezed := _sample[to] - low
	var chord := joints[to] - a
	if chord.length() < 0.001 or squeezed.length() < 0.001:
		return
	var offset := joints[mid] - a
	var along := offset.dot(chord) / chord.length_squared()
	var bend := _across(offset - chord * along, squeezed) * (squeezed.length() / chord.length())
	_sample[mid] = low + squeezed * along + bend


## `bend` (a rig vector, x y over the floor and z up) in the 3D frame, with what lies along `chord`
## taken out.
static func _across(bend: Vector3, chord: Vector3) -> Vector3:
	var turned := Vector3(bend.x, bend.z, bend.y)
	var unit := chord.normalized()
	return turned - unit * turned.dot(unit)


## How high a fallen body's joint is held over the floor now: `CharacterMeshConfig.lying_clear`,
## eased in over `LIE_FRAMES` after it died, so a joint near the floor does not jump at the moment
## of death. Read only once dead.
func _floor_clearance() -> float:
	var eased := clampf(float(Engine.get_physics_frames() - _died) / LIE_FRAMES, 0.0, 1.0)
	return CharacterMeshConfig.lying_clear * eased


## The way each fist faces, flat, into the sample: the 2D hand's own angle while the body lives
## (what the painter turns the fist by), else along the forearm.
func _sample_fists(rig: Object, body: Node2D) -> void:
	if _died < 0:
		var angles: Array = body.anatomy.pose.hand_angles
		for i in 2:
			var angle: float = angles[i]
			_sample[FISTS + i] = Vector3(cos(angle), 0.0, sin(angle))
		return
	for i in 2:
		var forearm: Vector3 = rig.point(Rig.HAND[i]) - rig.point(Rig.ELBOW[i])
		_sample[FISTS + i] = Vector3(forearm.x, 0.0, forearm.y)


## A direction of the rig (x, y over the floor, z up: flat for a standing body, tipped for a fallen
## one) as a direction in 3D.
func _dir(direction: Vector3) -> Vector3:
	return Vector3(direction.x, direction.z * _squeeze, direction.y)


## The look the dress resolved (what the painters read through the handle).
func _look() -> Dictionary:
	return PixelArt.look_of(_dress.head_opts)


## Part `index` made in `color`, as the vertex colour of its solid: a textured part shows it where
## its art is clear (`BodyTextures` tints it white, so the art shows as painted).
func _coat(index: int, color: Color) -> void:
	_skin.parts[index].mesh = _solid(SHAPES[index], color)


## The face band's colour: near black on a light skin and near white on a dark one, so the way the
## head looks reads from the height of the 3D camera at any zoom.
static func _band_colour(skin: Color) -> Color:
	return Color(0.08, 0.08, 0.1) if skin.get_luminance() > 0.3 else Color(0.92, 0.92, 0.9)


## `value` if it is a colour, else a neutral grey (a part its style names no colour for).
static func _colour(value: Variant) -> Color:
	return value if value is Color else Color.GRAY


## What `BodyMesh` reads once and many parts use: the look it is dressed for, whether that look's
## headwear is a cap, how high the highest dome of a living head reaches (head radii), and the way
## the face looks, flat (unit: what a steep limb's top turns toward, taken once a pose).
class Read:
	var look_key := -1
	var cap := false
	var top := 1.0
	var toward := Vector3.BACK
