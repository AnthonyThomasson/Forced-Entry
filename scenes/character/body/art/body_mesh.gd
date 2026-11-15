class_name BodyMesh
extends Node3D
## Character body, the 3D mesh of a living character (#193 phase 2, `domain-art/meshes.md`): a
## low-poly body of the mesh kit's solids that the 3D mirror shows in place of the character's proxy
## capsule. A trunk (the shirt, over it a vest, its plates and a pack), a head (skin, hair or a cap
## or helmet, a visor band across the front of the face), two arms, two hands and two legs with
## their shoes (a boot's shaft over the shin), each in the colour the 2D painters draw it in
## (`BodyDress`: the style, the outfit and the plates' colours).
##
## **Where the parts are** is the 2D body's own rig (`anatomy.rig()`, `character_rig.gd`): the same
## joints the painters draw the limbs between, solved once per physics frame and shared. They turn
## with the character's pose (not its node, which is never rotated), so the body faces where the 2D
## one does, the arms hold what the hands hold, the legs stride as the gait says and a crouch folds
## the spine and lowers the hips as `CharacterPostureConfig` says (docs/cover-and-stance.md P3). The
## rig's heights are the drawing's (a head 100 px up); the mesh squeezes them so the head stands
## `CharacterMeshConfig.height` high, and the horizontal reach is unchanged.
## **How it follows:** the parts are shared unit solids (one cylinder, one ball, one box;
## `MeshCache`) scaled and placed between the rig's joints by `mirror_update(body)` (the mirror
## calls
## it each frame the mesh shows), only when a joint moved; a new look (an outfit, a style) only
## re-tints and shows or hides the optional parts (`_dress_parts`).
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
## Sides of the shared round solids: the limbs, the trunk and the balls.
const LIMB_SIDES := 6
const TORSO_SIDES := 10
const BALL_SIDES := 8
## The parts, in `_parts`: the trunk's and the head's, then the sided ones (two each, side 0 first).
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
## The held item's node, after the parts (it is not one of the character's own).
const HELD := 23
## The parts too small to throw a shadow worth its cost (the face's band, the fists, the plates, the
## shoes and a boot's shaft, the hair and the headwear): the other twelve parts cast one.
const SMALL := [
	PLATE, PLATE + 1, HAIR, HEADWEAR, FACE, HAND, HAND + 1, BOOT, BOOT + 1, FOOT, FOOT + 1,
]
## The joints and the flat directions the pose is made from, in one array to compare a frame's with
## the last: the rig's seventeen joints, the two feet's toes and the face, and what the held item
## points along (flat x, y) and how far it is pitched up (z).
const JOINTS := 17
const SAMPLE := 21
## How far a joint (px) or a flat direction (its length, about 1 degree for 0.02) must move from the
## pose the parts are in to pose them again: a body at rest, its breath and its head's spring still
## settling, is not re-placed every frame. A joint's is under one pixel of the 3D picture.
const MOVED := 0.2
const TURNED := 0.02
## How far down the shin (0 knee .. 1 ankle) a boot's shaft starts, and how much wider than the
## shin it is.
const BOOT_TOP := 0.62
const BOOT_GROW := 1.15
## How many physics frames a fallen body's joints take to rise to their clearance over the floor.
const LIE_FRAMES := 18
## The held item's sample: its index among the joints.
const AIM := JOINTS + 3
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
const PLATE_AT := 0.3

## The body's radius, the visuals' dress, the hands' size and the head's.
var _r := 14.0
var _dress: BodyDress
var _hand_radius := 4.0
var _head_radius := 5.0
## How the rig's heights are squeezed (`CharacterMeshConfig.height`).
var _squeeze := 1.0
## The physics frame last posed, the joints it was posed from (sized once, copied into: no array
## is made per frame), whether `_last` holds a pose the parts are in, and the look it was dressed
## for.
var _frame := -1
var _last := PackedVector3Array()
var _sample := PackedVector3Array()
var _posed := false
var _look_key := -1
## Whether the head covering is a cap (else a helmet).
var _cap := false
## The parts, by the indices above (a sided part's own is its index plus the side).
var _parts: Array[MeshInstance3D] = []
## What the character holds (`BodyHeld`: its node is the last child, `HELD`).
var _held := BodyHeld.new()
## The physics frame the body died in (-1 while it lives: it follows the ragdoll from then), and
## whether it was posed at rest (the ragdoll asleep).
var _died := -1
var _at_rest := false


## The body of `body` (a character with its `Visuals` dress), or null for a node that is none: the
## mirror then keeps its proxy.
static func build(body: Node2D) -> Node3D:
	var visuals: Node = body.get_node_or_null("Visuals")
	if not body is CharacterBody2D or visuals == null or not visuals.get("dress") is BodyDress:
		return null
	if body.get("anatomy") == null or not body.get("wardrobe") is CharacterWardrobe:
		return null
	var mesh := BodyMesh.new()
	mesh._make(body as CharacterBody2D, visuals.get("dress"))
	return mesh


## Place the parts between the joints the rig holds now, once for each physics frame and only when a
## joint moved, and dress them again when the look changed.
func mirror_update(body: Node2D) -> void:
	if _died < 0:
		# The 2D visuals refresh the dress only for a body inside the 2D view, which the 3D camera
		# outruns; the call is cheap and answers at once when nothing changed.
		_dress.refresh(body.wardrobe)
		if _dress.look_key != _look_key:
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
	_at_rest = ragdoll.is_settled()
	_pose(ragdoll, body)


## The body died: it keeps following, now the 2D ragdoll's joints, unless the ragdoll is not there
## (then the mirror hides it). The held item goes with the hand that held it.
func on_body_died(body: Node2D) -> bool:
	if not body.anatomy.ragdoll is Fallen:
		return false
	_died = Engine.get_physics_frames()
	_at_rest = false
	_posed = false
	_frame = -1
	return true


## The node showing what the character holds, hidden while nothing is (the held slot's item has no
## mesh: fists, an empty hand, a key), or the body is dead.
func held() -> MeshInstance3D:
	return _held.node


## Make the parts of `body`, dressed in `dress`, and pose them.
func _make(body: CharacterBody2D, dress: BodyDress) -> void:
	_dress = dress
	_r = body.radius
	var hands: Node = body.get_node_or_null("Hands")
	if hands != null and hands.get("hand_radius") is float:
		_hand_radius = hands.get("hand_radius")
	_head_radius = CharacterArtConfig.head_size * 2.0 * _r * CharacterMeshConfig.head_scale
	_squeeze = (
		maxf(CharacterMeshConfig.height - _head_radius, 1.0)
		/ (CharacterBodyConfig.head_height * _r)
	)
	_sample.resize(SAMPLE)
	_last.resize(SAMPLE)
	var solids := {
		&"limb": _unit(&"cylinder", LIMB_SIDES),
		&"trunk": _unit(&"cylinder", TORSO_SIDES),
		&"ball": _unit(&"ball", BALL_SIDES),
		&"box": _unit(&"box", 0),
	}
	var shapes := [
		&"trunk", &"trunk", &"box", &"box", &"box", &"ball", &"ball", &"ball", &"box",
		&"limb", &"limb", &"limb", &"limb", &"ball", &"ball", &"limb", &"limb", &"limb", &"limb",
		&"limb", &"limb", &"box", &"box",
	]
	for i in shapes.size():
		var node := MeshNodes.instance(solids[shapes[i]], Color.WHITE, not SMALL.has(i))
		MeshNodes.figure(node)
		add_child(node)
		_parts.append(node)
	assert(_parts.size() == FOOT + 2, "BodyMesh: the shapes list and the part indices disagree")
	add_child(_held.node)
	assert(_held.node.get_index() == HELD, "BodyMesh: the held item's node is not after the parts")
	_dress_parts()
	_pose(body.anatomy.rig(), body)


## The shared unit solid `shape` (a cylinder of radius 1 px and height 1 px from the origin up, a
## ball of radius 1 at the origin, a box 1 px each way over the origin's column), `sides` flat faces
## round (the cylinder's and the ball's). One mesh for every body.
static func _unit(shape: StringName, sides: int) -> Mesh:
	var key := MeshCache.key(
		"body_part",
		Vector2.ONE,
		Color.WHITE,
		{ "shape": shape, "sides": sides },
	)
	return MeshCache.fetch(key, _make_unit.bind(shape, sides))


## The mesh of `_unit`.
static func _make_unit(shape: StringName, sides: int) -> Mesh:
	var kit := MeshKit.new()
	kit.sides = sides
	match shape:
		&"cylinder":
			kit.cylinder(Vector3.ZERO, 1.0, 1.0, Color.WHITE)
		&"ball":
			kit.sphere(Vector3.ZERO, 1.0, Color.WHITE)
		_:
			kit.box(AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE), Color.WHITE)
	return kit.build()


## Colour the parts from the look the dress resolved, and show the optional ones it asks for: the
## vest and its plates, a pack, hair or a cap or helmet, a boot's shaft.
func _dress_parts() -> void:
	_look_key = _dress.look_key
	var look := _look()
	var skin := _dress.skin
	_tint(_parts[TORSO], _dress.shirt)
	var vest := String(look.get("vest", "")) != ""
	_tint(_parts[VEST], _colour(look.get("vest_col")))
	_parts[VEST].visible = vest
	for i in 2:
		var plate: Variant = _dress.shoulder_opts.get("front_plate" if i == 0 else "back_plate")
		_parts[PLATE + i].visible = vest and plate is Color
		_tint(_parts[PLATE + i], _colour(plate))
	_tint(_parts[PACK], _colour(look.get("pack_col")))
	_parts[PACK].visible = bool(look.get("pack", false))
	_tint(_parts[HEAD], skin)
	_tint(_parts[FACE], _band_colour(skin))
	var worn := String(look.get("head", ""))
	var covered := worn == "helmet" or worn == "cap"
	_cap = worn == "cap"
	_parts[HEADWEAR].visible = covered
	_tint(_parts[HEADWEAR], _colour(look.get("helm")))
	_parts[HAIR].visible = not covered and String(look.get("hair_style", "short")) != "bald"
	_tint(_parts[HAIR], _colour(look.get("hair")))
	for i in 2:
		_tint(_parts[UPPER + i], _colour(_dress.arm_parts[i]["upper"]["color"]))
		_tint(_parts[FORE + i], _colour(_dress.arm_parts[i]["fore"]["color"]))
		_tint(_parts[HAND + i], _colour(_dress.hand_parts[i]["color"]))
		_tint(_parts[THIGH + i], _dress.pants)
		_tint(_parts[SHIN + i], _dress.shin_colour(i))
		_parts[BOOT + i].visible = _dress.boots
		_tint(_parts[BOOT + i], _dress.shoes)
		_tint(_parts[FOOT + i], _dress.shoes)


## Place every part between the joints of `rig` (the standing skeleton, or a ragdoll: the same
## indices and reads), unless none moved since the last time. `body` is the character, whose held
## item rides on the hand.
func _pose(rig: Object, body: Node2D) -> void:
	var clear := _floor_clearance()
	for i in JOINTS:
		_sample[i] = _lift(rig.point(i), clear)
	for i in 2:
		_sample[JOINTS + i] = _dir(rig.toes(i))
	_sample[JOINTS + 2] = _dir(rig.face())
	_sample[AIM] = _held.sample(body, _died >= 0)
	if _held.swapped:
		_held.swapped = false
		_posed = false  # a new item has not been placed
	if _posed and _unmoved():
		return
	_posed = true
	for i in SAMPLE:
		_last[i] = _sample[i]
	_pose_trunk()
	_pose_head()
	for i in 2:
		_pose_limbs(i)
	_held.place(_last[AIM], _last[Rig.HAND[_held.hand]])


## Whether every joint of `_sample` is within `MOVED`, and every direction within `TURNED`, of the
## pose the parts are in.
func _unmoved() -> bool:
	for i in SAMPLE:
		var step := MOVED if i < JOINTS else TURNED
		if _sample[i].distance_squared_to(_last[i]) > step * step:
			return false
	return true


## The trunk from the pelvis up the spine past the chest, with its vest, plates and pack.
func _pose_trunk() -> void:
	var pelvis := _last[Rig.PELVIS]
	var up := _last[Rig.CHEST] - pelvis
	var frame := _frame_of(up, _last[Rig.BELLY] - _last[Rig.SPINE])
	var half := _trunk_half()
	var length := up.length() + CharacterMeshConfig.torso_overshoot * _r
	_place(_parts[TORSO], frame, Vector3(half.x, length, half.y), pelvis)
	_pose_vest(frame, pelvis, up.length(), half)
	_pose_pack(frame, pelvis, up.length(), half)


## The trunk's half width and half depth (px).
func _trunk_half() -> Vector2:
	return Vector2(
		CharacterMeshConfig.torso_width,
		CharacterArtConfig.shoulder_depth * CharacterMeshConfig.torso_depth,
	) * _r


## The vest over the trunk (`frame` from `pelvis`, `spine` long, `half` its half width and depth),
## and a plate on its front and back.
func _pose_vest(frame: Basis, pelvis: Vector3, spine: float, half: Vector2) -> void:
	var grow := CharacterMeshConfig.vest_grow
	var from := spine * CharacterMeshConfig.vest_from
	var length := spine + CharacterMeshConfig.torso_overshoot * _r - from
	_place(
		_parts[VEST],
		frame,
		Vector3(half.x * grow, length, half.y * grow),
		pelvis + frame.y * from,
	)
	var plate := CharacterMeshConfig.plate_size * _r
	var thick := CharacterMeshConfig.plate_thickness
	var shell := half.y * grow + thick * 0.5
	for i in 2:
		_place(
			_parts[PLATE + i],
			frame,
			Vector3(plate.x, plate.y, thick),
			pelvis + frame.y * spine * PLATE_AT + frame.z * (shell if i == 0 else -shell),
		)


## The pack behind the trunk (arguments as `_pose_vest`).
func _pose_pack(frame: Basis, pelvis: Vector3, spine: float, half: Vector2) -> void:
	var pack := Vector3(
		half.x * CharacterMeshConfig.pack_width * 2.0,
		spine * CharacterMeshConfig.pack_height,
		CharacterMeshConfig.pack_depth,
	)
	var behind := half.y * CharacterMeshConfig.vest_grow + pack.z * 0.5
	_place(_parts[PACK], frame, pack, pelvis + frame.y * spine * 0.15 - frame.z * behind)


## The head on its joint, its hair or headwear toward the back and its face band where the face
## looks.
func _pose_head() -> void:
	var at := _last[Rig.HEAD]
	# A living head is upright on its neck; a fallen one lies as its neck does.
	var up := _last[Rig.HEAD] - _last[Rig.CHEST] if _died >= 0 else Vector3.UP
	var frame := _frame_of(up, _last[JOINTS + 2])
	var r := _head_radius
	_place(_parts[HEAD], frame, Vector3(r, r, r), at)
	_cover(_parts[HAIR], frame, HAIR_SHAPE, at)
	_cover(
		_parts[HEADWEAR],
		frame,
		CAP_SHAPE if _cap else HELMET_SHAPE,
		at,
	)
	_place(
		_parts[FACE],
		frame,
		FACE_SHAPE * r,
		at + frame.z * r * FACE_FORWARD + frame.y * r * FACE_BASE,
	)


## `node` (a ball) over the head at `at`: `shape` is its size over the head's, how far up and how
## far back it sits.
func _cover(node: MeshInstance3D, frame: Basis, shape: Vector3, at: Vector3) -> void:
	var r := _head_radius
	_place(
		node,
		frame,
		Vector3(shape.x, shape.x * 0.85, shape.x) * r,
		at + frame.y * r * shape.y - frame.z * r * shape.z,
	)


## Side `i`'s arm (shoulder, elbow, hand) and leg (hip, knee, ankle, with its boot and foot).
func _pose_limbs(i: int) -> void:
	var arms := CharacterArtConfig.body_arm_widths
	var thick := _r * 0.5 * CharacterMeshConfig.limb_scale
	var elbow := _last[Rig.ELBOW[i]]
	var hand := _last[Rig.HAND[i]]
	_segment(_parts[UPPER + i], _last[Rig.SHOULDER[i]], elbow, (arms[0] + arms[1]) * 0.5 * thick)
	_segment(_parts[FORE + i], elbow, hand, (arms[1] + arms[2]) * 0.5 * thick)
	_place(_parts[HAND + i], Basis.IDENTITY, Vector3.ONE * _hand_radius, hand)
	_pose_leg(i, thick)


## Side `i`'s leg, its limbs `thick` px across the widths: the thigh, the shin (and a boot's shaft
## over it) and the shoe under the ankle, pointing where the toes do.
func _pose_leg(i: int, thick: float) -> void:
	var legs := CharacterArtConfig.body_leg_widths
	var knee := _last[Rig.KNEE[i]]
	var ankle := _last[Rig.ANKLE[i]]
	var shin: float = (legs[1] + legs[2] + legs[3]) / 3.0 * thick
	_segment(_parts[THIGH + i], _last[Rig.HIP[i]], knee, (legs[0] + legs[1]) * 0.5 * thick)
	_segment(_parts[SHIN + i], knee, ankle, shin)
	_segment(_parts[BOOT + i], knee.lerp(ankle, BOOT_TOP), ankle, shin * BOOT_GROW)
	var shoes := CharacterArtConfig.body_shoe_widths
	var size := Vector3(
		(shoes[0] + shoes[1]) * 0.5 * _r * CharacterMeshConfig.limb_scale,
		CharacterMeshConfig.foot_height * _r,
		CharacterBodyConfig.foot * _r,
	)
	var frame := _frame_of(Vector3.UP, _last[JOINTS + i])
	var at := Vector3(ankle.x, maxf(ankle.y - size.y * 0.5, 0.0), ankle.z)
	_place(_parts[FOOT + i], frame, size, at + frame.z * size.z * 0.25)


## `node` (a unit cylinder) laid from `from` to `to`, `radius` px across.
func _segment(node: MeshInstance3D, from: Vector3, to: Vector3, radius: float) -> void:
	var along := to - from
	_place(
		node,
		_frame_of(along, Vector3.BACK),
		Vector3(radius, maxf(along.length(), 0.01), radius),
		from,
	)


## `node` turned to `frame`, `size` px along its three axes, its origin at `at` px; a part not shown
## is left where it is (the look that shows it poses again).
func _place(node: MeshInstance3D, frame: Basis, size: Vector3, at: Vector3) -> void:
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


## How high a joint is held over the floor now: nothing while the body lives, then
## `CharacterMeshConfig.lying_clear` eased in over `LIE_FRAMES` after it died, so a joint near the
## floor does not jump at the moment of death.
func _floor_clearance() -> float:
	if _died < 0:
		return 0.0
	var eased := clampf(float(Engine.get_physics_frames() - _died) / LIE_FRAMES, 0.0, 1.0)
	return CharacterMeshConfig.lying_clear * eased


## A direction of the rig (x, y over the floor, z up: flat for a standing body, tipped for a fallen
## one) as a direction in 3D.
func _dir(direction: Vector3) -> Vector3:
	return Vector3(direction.x, direction.z * _squeeze, direction.y)


## The look the dress resolved (what the painters read through the handle).
func _look() -> Dictionary:
	return PixelArt.look_of(_dress.head_opts)


## `node` tinted `color` (its own colour: the shared meshes are white).
static func _tint(node: MeshInstance3D, color: Color) -> void:
	node.set_instance_shader_parameter(&"base_color", color)


## The face band's colour: near black on a light skin and near white on a dark one, so the way the
## head looks reads from the height of the 3D camera at any zoom.
static func _band_colour(skin: Color) -> Color:
	return Color(0.08, 0.08, 0.1) if skin.get_luminance() > 0.3 else Color(0.92, 0.92, 0.9)


## `value` if it is a colour, else a neutral grey (a part its style names no colour for).
static func _colour(value: Variant) -> Color:
	return value if value is Color else Color.GRAY
