extends Node2D
## Character DRAW layer. Renders the whole character as top-down pixel art (painted through the Art
## domain's PixelArt), each part at its own angle from the character's pose and each limb from the
## joints of its rig: a drop shadow, the legs and shoes, the arms (sleeve, then forearm), the
## shoulders at the pose's lunge, the head (with its shadow on the shoulders) shifted by the pose's
## lean and breath, then the item's own weapon, the fists gripping it, and last the wound marks.
## Shots dent and darken the shoulders and any part they passed through. Each part is lit for the
## nearest lighting step and drawn rotated to its exact angle. Reads the body radius, pose, rig,
## held item and wounds from the character and hand positions/size from the hands sibling.
## Appearance only — no item-specific weapon logic lives here (that's each Item's draw_weapon()).
## Once dead it draws the fallen ragdoll instead. How it looks is its style (`Character.style`,
## `look_seed`, `rank`; `docs/outfits.md`, styles) and what it wears drawn in that style (`_dress`,
## through `character_style.gd`): the headwear, the shirt and its sleeves, a vest and its plates'
## wear, the pants and the footwear, and its own skin, hair, gloves, pack and implants.

const BodyPainter = preload("res://scenes/character/body/art/body_painter.gd")
const HeadPainter = preload("res://scenes/character/body/art/head_painter.gd")
const HandPainter = preload("res://scenes/character/body/art/hand_painter.gd")
const LimbPainter = preload("res://scenes/character/body/art/limb_painter.gd")
const TorsoPainter = preload("res://scenes/character/body/art/torso_painter.gd")
const VestPainter = preload("res://scenes/character/body/art/vest_painter.gd")
const CharacterStyle = preload("res://scenes/character/body/character_style.gd")
const BodyMeshes = preload("res://scenes/character/body/body_meshes.gd")
# The joint indices, shared with the ragdoll.
const Rig = preload("res://scenes/character/body/character_rig.gd")
const Pose = preload("res://scenes/character/body/character_pose.gd")
## A standing body is repainted only when what it draws has changed: its joints, the angles its
## parts are turned by, what is held and its wounds, each rounded to a step below a visible pixel at
## the body's size (positions in px, angles in rad). A character standing still drifts by less than
## a step most frames (breath, glance), and repainting an identical body is most of an idle crowd's
## frame cost.
const REDRAW_POS_STEP := 0.1
const REDRAW_ANGLE_STEP := 0.02
## How far a held weapon's raise (0..1) must change to repaint: the gun's art steps through a few
## lengths.
const REDRAW_RAISE_STEP := 0.1
## How folded (0..1) a crouching body is before it is drawn from the rig's trunk (its back showing),
## not as shoulders.
const FOLD_DRAW := 0.15
## A hand gripping lower than this (body radii off the floor: relaxed 3.7, running ~4-5.8) hangs
## below the shoulders and is drawn under them.
const HAND_OVER_HEIGHT := 5.0
## A hand gripping at least this high (body radii: the `eyes` stance, 7.0; every other stance 6.8 or
## lower) is over the face and is drawn after the head, which covers every other hand.
const HAND_ON_FACE_HEIGHT := 6.9
## Px beyond the camera's view inside which a body is still drawn: the longest reach of a limb or a
## held gun past the body centre, so a part poking into view from a body just outside it is never
## missing.
const CULL_MARGIN := 120.0
## How far down the shin (0 knee .. 1 ankle) a boot's shaft reaches, and how much wider (body radii)
## a boot is than a shoe.
const BOOT_TOP := 0.62
const BOOT_GROW := 0.06
## No painter options: the plain strip.
const _PLAIN := {}
## Points sampled around each trunk cross-section and each limb end.
const SECTION_POINTS := 16
const CAP_POINTS := 6
## Cross-sections the trunk's outline is lofted through between its ends, and in each end's dome.
const TRUNK_STEPS := 10
const DOME_STEPS := 3
## How far past the end sections the domes reach (spine fractions): over the shoulders, under the
## hips.
const DOME_TOP := 0.12
const DOME_BOTTOM := 0.1
## Px each slice of the trunk's outline grows by so neighbouring slices overlap in area, and the
## area (px²) above which a piece of their union counts as a body part rather than a sliver.
const HULL_OVERLAP := 0.5
const PIECE_MIN_AREA := 1.0
## A wound shows once its patch of skin turns at least this far (its normal's z) to the camera.
const WOUND_MIN_FACING := 0.3
## Parts whose heights differ by less than this (px) keep the order they were drawn in last frame.
const STACK_BAND := 3.0

## How much the ends' radii of a convex capsule may differ, per px of its length: under the tangent
## of a cap's half step (15°), with room.
static var CAP_CONVEX := tan(PI / (2.0 * CAP_POINTS)) * 0.9
## Unit points round a capsule's ends in its own frame (x along it): the cap behind `a` from one
## side round to the other, the cap ahead of `b`, and the whole round of a capsule whose ends meet.
## `_capsule` turns, scales and places them.
static var _CAP_BEHIND := _arc(PI * 0.5, PI / CAP_POINTS, CAP_POINTS + 1)
static var _CAP_AHEAD := _arc(-PI * 0.5, PI / CAP_POINTS, CAP_POINTS + 1)
static var _CAP_ROUND := _arc(0.0, TAU / (CAP_POINTS * 2), CAP_POINTS * 2)
## The unit ring a trunk cross-section is sampled on (`_trunk_hulls`): point `k` at angle
## `TAU * k / SECTION_POINTS`.
static var _SECTION_RING := _ring(SECTION_POINTS)

## Draws the body's floor shadow; inside a CanvasGroup (which carries the shadow's alpha) so
## overlapping parts don't darken twice.
var _shadow: Node2D
## The textured parts drawn on the body and on its shadow, as meshes kept from draw to draw.
var _meshes: BodyMeshes
var _shadow_meshes: BodyMeshes
## The fallen body has been drawn at rest: nothing left to redraw.
var _settled_drawn := false
## The fallen parts' keys, lowest first, as last drawn (see `_stack`).
var _fallen_order: Array[String] = []
## The standing skeleton solved this frame, shared by the body's and the shadow's draw.
var _rig: Rig
## The body was outside the camera's view last frame, so nothing was repainted.
var _offscreen := false
## The rounded inputs the standing body was last repainted for.
var _redraw_key := PackedInt32Array()
## How many times the standing body has been drawn (tests read it).
var redraws := 0
## What the last living draw painted over the body, in order (tests read it).
var draw_order: Array[StringName] = []
## The textures the last draw of the body painted, in order (`drawn_art`).
var _art: Array[Texture2D] = []
## How the round part being drawn is drawn: one look, refilled for each part (`_round_look`).
var _look := ShapeLook.new()
## The look as drawn: the character's style and what it wears in it. Resolved by `_dress` only when
## the outfit (`Outfit.revision`) or the style (`Character.style`, `look_seed`, `rank`) changes, so
## the per-frame cost is two ints compared.
## The outfit revision the look was last resolved for.
var _worn_revision := -1
## The character's look revision (its style, seed and rank) it was last resolved for.
var _style_revision := -1
## A hash of the resolved look: joins the redraw key, and repaints a settled fallen body when it
## changes.
var _look_key := 0
## The shoulders, the trunk and a sleeve.
var _shirt := Color.WHITE
## The thighs and shins.
var _pants := Color.WHITE
## The shoes, and a boot's shaft.
var _shoes := Color.WHITE
## Boots: a laced shaft up the shin over the shoe.
var _boots := false
## The neck, the head's skin and bare arms.
var _skin := Color.WHITE
## The fists: gloves, or bare skin.
var _glove := Color.WHITE
## A chrome limb.
var _chrome := Color.WHITE
## BodyPainter's options (the look's handle, the plates and their wear).
var _shoulder_opts := {}
## TorsoPainter's options by face ("front" / "back" / "side").
var _torso_opts := {}
## HeadPainter's options.
var _head_opts := {}
## Per side: each arm segment ("upper", "fore") as `{ color, material, opts }`: a sleeve, bare skin
## or chrome.
var _arm_parts: Array[Dictionary] = []
## Per side: LimbPainter's options by leg part ("thigh", "knee", "shin", "shaft", "foot").
var _leg_opts: Array[Dictionary] = []
## Per side: the shin is chrome.
var _chrome_shin: Array[bool] = [false, false]
## Per hand: the fist's `color` and painter `opts`.
var _hand_parts: Array[Dictionary] = []
## The limb chains last built (`_limbs`), the joints they were built from and the physics frame.
var _limb_chains: Array = []
var _limbs_of: RefCounted = null
var _limbs_frame := -1

## Character — body radius, pose, rig, held item.
@onready var _character := get_parent()
## Sibling — hand positions / size.
@onready var _hands := $"../Hands"


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_meshes = BodyMeshes.new(self)
	_build_shadow()
	_dress()


func _process(_delta: float) -> void:
	_limbs_of = null  # The limb chains are shared by this frame's two draws only (`_limbs`).
	if not _in_view():
		if not _offscreen:
			_offscreen = true
			# Whatever changes off screen, the first frame back repaints.
			_redraw_key = PackedInt32Array()
		return
	_offscreen = false
	var ragdoll = _character.ragdoll
	if ((_character.outfit().revision != _worn_revision
			or _character._look_revision != _style_revision)
			and _dress()):
		_settled_drawn = false  # A body at rest repaints what it now wears.
	if ragdoll == null:
		_rig = _character.rig()
		var key := _redraw_key_of(_rig)
		if key != _redraw_key:
			_redraw_key = key
			queue_redraw()
			_shadow.queue_redraw()
		return
	if _settled_drawn:
		return
	_settled_drawn = ragdoll.is_settled()
	queue_redraw()
	_shadow.queue_redraw()


func _draw() -> void:
	_art.clear()
	_meshes.begin()
	if _character.ragdoll:
		_draw_fallen(_character.ragdoll)
		return
	redraws += 1
	draw_order.clear()
	var rig: Rig = _rig if _rig != null else _character.rig()
	if draws_laid_out():
		_draw_lying(rig)
		return
	_draw_standing(rig)


## The standing body from `rig`: the legs and arms, the weapon under the shoulders, a hanging hand
## under them too, the shoulders, the other fists, the head, a hand over the face, then the wounds.
func _draw_standing(rig: Rig) -> void:
	var pose: Pose = _character.pose
	# The shoulders sit where the rig puts the chest: the torso's lunge, plus the forward shift of a
	# folded spine, so the sleeves meet them in a crouch.
	var lunge := _rig_xy(rig, Rig.CHEST)
	var deformable = _character._deformable
	# Impacts are recorded relative to the shoulders (character.take_hit), so they turn with them.
	var impacts := _turned(deformable.impacts if deformable else [], pose.torso_angle)
	# The same wounds in the character's frame, for the parts.
	var placed := _shifted(impacts, lunge)
	var damage_total: float = deformable.damage_total if deformable else 0.0
	var item: Item = _character.current_item()

	for chain in _limbs(rig):  # The legs, then the arms.
		_draw_chain(chain)
	# The weapon goes under the torso: its butt is tucked behind the shoulder, the barrel shows
	# beyond.
	if item:
		item.draw_weapon(self, _character)
		draw_order.append(&"weapon")
	# A hand hanging at the side (below HAND_OVER_HEIGHT) is lower than the shoulders, so they cover
	# it.
	var hung: Array[int] = []
	for hand in 2:
		if pose.grip_height(hand) < HAND_OVER_HEIGHT:
			hung.append(hand)
			_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, placed, damage_total)
	_draw_shoulders(pose, lunge, impacts, damage_total)
	for hand in 2:
		if not hung.has(hand) and pose.grip_height(hand) < HAND_ON_FACE_HEIGHT:
			_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, placed, damage_total)
	draw_order.append(&"hands")
	_draw_head(pose, rig, placed, damage_total)  # The highest part: over the gun and the fists.
	draw_order.append(&"head")
	_draw_face_hands(pose, placed, damage_total)
	# Wound marks over everything, so a hit hand shows its wound: dark-red holes and cracks that
	# read as bloody gashes (config-driven).
	Deformation.draw_marks(self, placed, CharacterConfig.flesh_crack_color,
		CharacterConfig.flesh_hole_color, CharacterConfig.flesh_scorch_color)


## The shoulders at the `lunge`: the art through the flesh silhouette deformed by the shots
## (`impacts`, in the shoulders' frame: dents, and darkening by `damage_total`).
func _draw_shoulders(pose: Pose, lunge: Vector2, impacts: Array, damage_total: float) -> void:
	var torso: float = pose.torso_angle - PI * 0.5  # Canonical art faces +y.
	var body := _shoulder_art(torso)
	draw_set_transform(lunge, 0.0, Vector2.ONE)
	_art.append(body)
	_draw_round(
		_shoulder_size(),
		impacts,
		_round_look(body, torso, damage_total, _shirt, CharacterConfig.flesh_crack_color),
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_order.append(&"torso")


## Whether the body is within `CULL_MARGIN` px of the camera's view: the viewport's visible rect
## taken back into world space through its canvas transform. A body outside it is not solved or
## repainted (its last drawing stays, unseen); with no viewport it counts as in view.
func _in_view() -> bool:
	var vp := get_viewport()
	if vp == null:
		return true
	var seen: Rect2 = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	return seen.grow(CULL_MARGIN).has_point(global_position)


## The inputs of the standing draw for `rig`, each rounded to its redraw step: the joints and feet
## (which carry the lunge, the head's offset and the hands' places), the angles the shoulders, head,
## fists and weapon are turned by, the held slot, and the wounds that dent and darken the parts.
func _redraw_key_of(rig: Rig) -> PackedInt32Array:
	var pose = _character.pose
	var key := PackedInt32Array()
	for i in 17:
		var p: Vector3 = rig.point(i)
		key.append(roundi(p.x / REDRAW_POS_STEP))
		key.append(roundi(p.y / REDRAW_POS_STEP))
		key.append(roundi(p.z / REDRAW_POS_STEP))
	for i in 2:
		var toes: Vector3 = rig.toes(i)
		key.append(roundi(toes.x / REDRAW_ANGLE_STEP))
		key.append(roundi(toes.y / REDRAW_ANGLE_STEP))
	for angle in [
			pose.torso_angle,
			pose.head_angle,
			pose.hand_angles[0],
			pose.hand_angles[1],
			pose.weapon_angle,
	]:
		key.append(roundi(angle / REDRAW_ANGLE_STEP))
	key.append(_character.current_slot())
	# A raised gun is drawn shorter.
	key.append(roundi(_character.weapon_raise() / REDRAW_RAISE_STEP))
	for hand in 2:
		# A punch swings a long gun round.
		key.append(roundi(_character.punch_amount(hand) / REDRAW_RAISE_STEP))
	var deformable = _character._deformable
	if deformable:
		key.append(deformable.impacts.size())
		key.append(roundi(deformable.damage_total * 100.0))
	key.append(_look_key)
	return key


## The textures the last draw of the body painted (standing, crouched or fallen), in order: its
## limbs, fists, shoulders or trunk and head (not the held item's). Pixel art is cached by what it
## depicts, so the same drawing gives the same textures.
func drawn_art() -> Array:
	return _art.duplicate()


## Resolve the look: the character's style (`Character.style`, with its `look_seed` and `rank`) and
## what it wears drawn in that style (`Outfit.look(style)`), through `character_style.gd`,
## registered for the painters (`PixelArt.handle`: they get its handle); then what each part is
## drawn in: the shirt, pants and shoes (boots: a laced shaft up the shin), the skin, the gloves,
## each arm's sleeve, bare skin or chrome, a chrome shin, each fist, and the plates' colours and
## wear, rounded to `VestPainter.WEAR_STEPS`. Returns whether the resolved look changed.
func _dress() -> bool:
	var outfit: Outfit = _character.outfit()
	_worn_revision = outfit.revision
	_limbs_of = null
	_style_revision = _character._look_revision
	var style: StringName = _character.style
	var worn := outfit.look(style)
	var look := CharacterStyle.resolve(style, _character.look_seed, _character.rank, worn)
	var id := PixelArt.handle(look)
	_shirt = _colour(look["shirt"])
	_pants = _colour(look["pants_col"])
	_shoes = _colour(look["feet_col"])
	_boots = look["feet"] == "boots"
	_skin = look["skin"]
	_glove = look["glove"]
	_chrome = look["chrome"]
	_shoulder_opts = _dress_plates(worn, id)
	_torso_opts = {}
	for face in ["front", "back", "side"]:
		_torso_opts[face] = { "face": face, "pants": _pants }.merged(_shoulder_opts)
	_head_opts = { "look": id }
	_dress_sides(look, id)
	var key := hash([
		_shirt, _pants, _shoes, _boots, _skin, _arm_parts, _shoulder_opts, _head_opts, _leg_opts,
		_chrome_shin, _hand_parts,
	])
	if key == _look_key:
		return false
	_look_key = key
	return true


## The shoulders' painter options for the look's handle `id`: the plates `worn` and their wear,
## rounded to `VestPainter.WEAR_STEPS`, painted in fabric (`PixelArt`'s `material` option). The
## torso's options take them too.
static func _dress_plates(worn: Dictionary, id: int) -> Dictionary:
	var dress := { "look": id }
	for side in ["front", "back"]:
		var plate: Dictionary = worn.get(side + "_plate", {})
		if not plate.is_empty():
			dress[side + "_plate"] = plate.get("color", Color.GRAY)
			dress[side + "_wear"] = ceili((1.0
					- clampf(float(plate.get("condition", 1.0)), 0.0, 1.0))
					* VestPainter.WEAR_STEPS)
	dress["material"] = "fabric"
	return dress


## What each side is drawn in, from `look` (handle `id`): each arm segment, each leg part's options
## and a chrome shin, and each fist's colour (gloves, skin or chrome) and options.
func _dress_sides(look: Dictionary, id: int) -> void:
	_arm_parts = []
	_leg_opts = []
	_chrome_shin = []
	_hand_parts = []
	for i in 2:
		_arm_parts.append({
			"upper": _arm_part(look, id, i, "upper"),
			"fore": _arm_part(look, id, i, "fore"),
		})
		_leg_opts.append(_leg_parts(look, id, i))
		var chrome: bool = look["chrome_arm"][i]
		var hand := { "look": id, "side": -1 if i == 0 else 1 }
		if chrome:
			hand["chrome"] = true
		_hand_parts.append({ "color": _chrome if chrome else _glove, "opts": hand })


## Side `i`'s LimbPainter options by leg part in `look` (handle `id`), noting whether its shin is
## chrome (`_chrome_shin`). Each part's `material` (`PixelArt`'s option): the trousers fabric, a
## chrome shin metal, the boot's shaft and the shoe none.
func _leg_parts(look: Dictionary, id: int, i: int) -> Dictionary:
	var parts := {}
	for part in ["thigh", "knee", "shin", "shaft", "foot"]:
		parts[part] = { "look": id, "part": part, "side": i }
	_chrome_shin.append(look["chrome_leg"][i])
	if _chrome_shin[i]:
		parts["shin"]["chrome"] = true
	for part in ["thigh", "knee", "shin"]:
		parts[part]["material"] = "metal" if part == "shin" and _chrome_shin[i] else "fabric"
	return parts


## Side `side`'s arm segment `part` ("upper" to the elbow, "fore" to the fist) in `look` (handle
## `id`): chrome, a sleeve (a long one down to its cuff at the wrist) or bare skin, its painter
## options carrying its `material` (`PixelArt`'s option: metal, fabric, none for skin).
func _arm_part(look: Dictionary, id: int, side: int, part: String) -> Dictionary:
	var opts := { "look": id, "part": part, "side": side }
	if look["chrome_arm"][side]:
		opts["chrome"] = true
		opts["material"] = "metal"
		return { "color": _chrome, "opts": opts }
	var sleeve: Variant = look["sleeves"][side]
	if sleeve != null and (part == "upper" or look["body"] == "long_sleeves"):
		opts["cuff"] = part == "fore"
		opts["material"] = "fabric"
		return { "color": sleeve, "opts": opts }
	opts["skin"] = true
	return { "color": _skin, "opts": opts }


## `value` if it is a colour, else a neutral grey (a part its style names no colour for).
static func _colour(value: Variant) -> Color:
	return value if value is Color else Color.GRAY


## Where the standing body's shoulders are drawn (local px): the rig's chest, so the sleeves meet
## them.
func shoulder_centre() -> Vector2:
	return _rig_xy(_character.rig(), Rig.CHEST)


## Where the standing body's head is drawn (local px): the rig's head.
func head_centre() -> Vector2:
	return _rig_xy(_character.rig(), Rig.HEAD)


## The floor-plane (x, y) of rig `joint`, dropping its height.
static func _rig_xy(rig: Rig, joint: int) -> Vector2:
	var p: Vector3 = rig.point(joint)
	return Vector2(p.x, p.y)


## Whether the living body is drawn laid out from the rig (like a fallen one: a lofted trunk showing
## its back, the limbs by height) rather than as upright shoulders: bent over in a crouch.
func draws_laid_out() -> bool:
	return _character.posture_folded() > FOLD_DRAW


## A crouched body: its parts from the rig's 3D points seen from above, lowest first, exactly as a
## fallen body is drawn (a lofted trunk showing its back, the limbs laid out), then what it holds
## and its fists on top.
func _draw_lying(rig: Rig) -> void:
	var pose = _character.pose
	var item: Item = _character.current_item()
	# The weapon goes under the trunk: its butt is tucked behind the shoulder, the barrel shows
	# beyond.
	var weapon := func() -> void:
		if item:
			item.draw_weapon(self, _character)
			draw_order.append(&"weapon")
	_draw_fallen(rig, false, weapon)
	for hand in 2:
		if pose.grip_height(hand) < HAND_ON_FACE_HEIGHT:
			_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, [], 0.0)
	draw_order.append(&"hands")
	_draw_fallen_head(_head_part(rig))  # The highest part: over the gun and the fists.
	draw_order.append(&"head")
	_draw_face_hands(pose, [], 0.0)


## A hand held over the face (a blinded character's palm over its eyes) is drawn over the head;
## `face_hand` joins the draw order when one is.
func _draw_face_hands(pose: Pose, placed: Array, damage_total: float) -> void:
	for hand in 2:
		if pose.grip_height(hand) >= HAND_ON_FACE_HEIGHT:
			_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, placed, damage_total)
			draw_order.append(&"face_hand")


## The shoulders' art canvas: the body's round footprint.
func _shoulder_size() -> Vector2:
	var r: float = _character.radius
	return Vector2(r * 2.0, r * 2.0)


## The shoulders' pixel art, lit for the nearest lighting step to `angle` (the art's turn).
func _shoulder_art(angle: float) -> Texture2D:
	return PixelArt.render_turned(
		BodyPainter,
		_shoulder_size(),
		_shirt,
		PixelArt.snap_angle(angle),
		_shoulder_opts,
	)


## The standing body's floor shadow, drawn into the shadow group: the shoulders' own silhouette
## through the deformed outline, then each limb, fist and the head, every point shifted away from
## the light by its height.
func _draw_standing_shadow() -> void:
	var rig: Rig = _rig if _rig != null else _character.rig()
	var shift := _shadow_shift()
	var lift := _draw_shoulders_shadow(rig, shift)
	var limbs := _limbs(rig)
	# All one black (the shadow group shows what any part covers, whatever the order): one kept
	# mesh, or without meshes one batch.
	var solid: BodyMeshes.Solid = null
	var fills: RefCounted = null
	if BodyMeshes.enabled:
		solid = _shadow_meshes.solid(Color.BLACK)
		fills = solid
	else:
		fills = FillBatch.new(_shadow)
	var bounds := Rect2(lift, Vector2.ZERO)  # What the limbs and the discs cover.
	for i in 2:
		for chain in [limbs[i], limbs[2 + i]]:
			bounds = bounds.merge(_draw_limb_shadow(chain, shift, fills))
		var hand := _cast(rig.point(Rig.HAND[i]), shift)
		fills.circle(hand, _hands.hand_radius, Color.BLACK)
		bounds = bounds.merge(Rect2(hand, Vector2.ZERO).grow(_hands.hand_radius))
	var head := _cast(rig.point(Rig.HEAD), shift)
	var head_radius: float = CharacterConfig.ragdoll_head_radius * _character.radius
	fills.circle(head, head_radius, Color.BLACK)
	if solid:
		solid.flush(bounds.merge(Rect2(head, Vector2.ZERO).grow(head_radius)))
	else:
		fills.flush()


## The shoulders' own deformed silhouette on the floor shadow, at the rig's chest (the lunge)
## shifted from the light (`shift`, per px of height). Returns where it lies.
func _draw_shoulders_shadow(rig: Rig, shift: Vector2) -> Vector2:
	var pose: Pose = _character.pose
	var deformable = _character._deformable
	var impacts := _turned(deformable.impacts if deformable else [], pose.torso_angle)
	var size := _shoulder_size()
	var angle: float = pose.torso_angle - PI * 0.5
	var poly := Deformation.shape_polygon("circle", size, impacts)
	# Undented, it is the intact ring already.
	if not impacts.is_empty() and not Deformation.is_valid_polygon(poly):
		poly = Deformation.base_ring("circle", size)
	var lift := _cast(rig.point(Rig.CHEST), shift)  # The shoulders' lunge, shifted from the light.
	_shadow_meshes.draw(
		Transform2D(0.0, lift) * poly,
		_texture_uvs(poly, size, angle),
		_shoulder_art(angle),
		Color.BLACK,
		Rect2(lift - size * 0.5, size),  # The round footprint: dents only cave in.
	)
	return lift


## Where each point of `poly` (local px) falls on art `size` px across drawn turned by `angle` about
## its centre: the uvs `Deformation.draw_shape` maps its texture with (the point turned back by
## `angle`, over the size, from the art's centre).
static func _texture_uvs(
	poly: PackedVector2Array,
	size: Vector2,
	angle: float,
) -> PackedVector2Array:
	var c := cos(angle)
	var s := sin(angle)
	var to_uv := Transform2D(Vector2(c / size.x, -s / size.y), Vector2(s / size.x, c / size.y),
			Vector2(0.5, 0.5))
	return to_uv * poly


## How far a point on the body is shifted on the floor shadow per px of its height: away from the
## light (see `_cast`).
func _shadow_shift() -> Vector2:
	return global_transform.basis_xform_inv(-ArtConfig.light_from.normalized()).normalized() \
		* CharacterConfig.body_shadow_per_height


## A 3D point's place on the floor shadow: its flat position shifted away from the light by its
## height (`shift`, from `_shadow_shift`, per px).
static func _cast(p: Vector3, shift: Vector2) -> Vector2:
	return Vector2(p.x, p.y) + shift * p.z


## One limb chain's floor shadow: each segment's capsule shifted from the light (`_cast`), added to
## `fills` (a `FillBatch` or a `BodyMeshes.Solid`). Returns the rect the capsules lie in.
func _draw_limb_shadow(chain: Dictionary, shift: Vector2, fills: RefCounted) -> Rect2:
	var bounds := Rect2()
	var reach := 0.0
	for seg in chain["segs"]:
		var a := _cast(seg["a"], shift)
		var b := _cast(seg["b"], shift)
		var ra: float = seg["ra"]
		var rb: float = seg["rb"]
		_fill_capsule(fills, _capsule(a, b, ra, rb), _convex(a, b, ra, rb), Color.BLACK)
		bounds = Rect2(a, Vector2.ZERO) if reach == 0.0 else bounds.expand(a)
		bounds = bounds.expand(b)
		reach = maxf(reach, maxf(seg["ra"], seg["rb"]))
	return bounds.grow(reach)


## The head at the pose's offset and angle, casting its shadow onto the shoulders first (the head
## sits above them, so its silhouette darkens them a few px away from the light).
func _draw_head(pose: Pose, rig: Rig, impacts: Array, damage_total: float) -> void:
	var px := ArtConfig.pixel_size
	var side := (float(HeadPainter.canvas_for(HeadPainter.radius_for(roundi(_character.radius * 2.0
			/ px)))) * px)
	var size := Vector2(side, side)
	var angle: float = pose.head_angle - PI * 0.5
	var tex := PixelArt.render_turned(
		HeadPainter,
		size,
		_skin,
		PixelArt.snap_angle(angle),
		_head_opts,
	)
	var at := _rig_xy(rig, Rig.HEAD)  # The pose's offset, plus the neck's pitch in a crouch.
	var drop := global_transform.basis_xform_inv(-ArtConfig.light_from.normalized()).normalized() \
		* ArtConfig.cast_shadow_px * px
	draw_set_transform(at + drop, angle, Vector2.ONE)
	draw_texture_rect(
		tex,
		Rect2(-size * 0.5, size),
		false,
		Color(0.0, 0.0, 0.0, ArtConfig.cast_shadow_darken),
	)
	_draw_part(at, size, impacts, _round_look(tex, angle, damage_total, _skin, _skin))


## A fist at the given hand (0 = right as drawn, 1 = left), turned to `angle`, dented by the shots
## that passed through where it is and darkened like the body.
func _draw_hand(hand: int, angle: float, impacts: Array, damage_total: float) -> void:
	var diameter: float = _hands.hand_radius * 2.0 + 2.0
	var size := Vector2(diameter, diameter)
	var part: Dictionary = _hand_parts[hand]
	var tex := PixelArt.render_turned(
		HandPainter,
		size,
		part["color"],
		PixelArt.snap_angle(angle),
		part["opts"],
	)
	var color: Color = part["color"]
	_draw_part(
		_hands.hand_position(hand),
		size,
		impacts,
		_round_look(tex, angle, damage_total, color, color),
	)


## One round part's art (`look.texture` spanning `size`) at `at`: through its silhouette dented by
## the shots that passed through it (`impacts`), darkened by the body's damage.
func _draw_part(at: Vector2, size: Vector2, impacts: Array, look: ShapeLook) -> void:
	_art.append(look.texture)
	draw_set_transform(at, 0.0, Vector2.ONE)
	_draw_round(size, _through(impacts, at, size.x * 0.5), look)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## How a round part is drawn (`_look`, refilled): its art `tex` turned by `angle` within its
## silhouette, darkened by `damage_total`, `fill` and `outline` its colours where it has no art, its
## hit marks left for later.
func _round_look(
	tex: Texture2D,
	angle: float,
	damage_total: float,
	fill: Color,
	outline: Color,
) -> ShapeLook:
	_look.fill = fill
	_look.outline = outline
	_look.damage_total = damage_total
	_look.texture = tex
	_look.texture_angle = angle
	_look.marks = false
	return _look


## A round part (`size` px across) drawn as `look` says, through its silhouette dented by `impacts`,
## at the draw transform, its hit marks left for later: what `Deformation.draw_shape` draws, in a
## kept mesh (`_meshes`): the polygon and uvs `draw_shape` maps the art onto (`_texture_uvs`), in
## white darkened as it darkens it (`Deformation.darken`). Without meshes (`BodyMeshes.enabled`)
## `draw_shape` draws it.
func _draw_round(size: Vector2, impacts: Array, look: ShapeLook) -> void:
	if not BodyMeshes.enabled:
		Deformation.draw_shape(self, "circle", size, impacts, look)
		return
	var poly := Deformation.shape_polygon("circle", size, impacts)
	if not impacts.is_empty() and not Deformation.is_valid_polygon(poly):
		poly = Deformation.base_ring("circle", size)
	_meshes.draw(
		poly,
		_texture_uvs(poly, size, look.texture_angle),
		look.texture,
		Color.WHITE.darkened(Deformation.darken(look.damage_total)),
		Rect2(-size * 0.5, size),
	)


## `impacts` turned by `angle`: from the shoulder-relative frame they're recorded in to the drawn
## one.
static func _turned(impacts: Array, angle: float) -> Array:
	var out := []
	for impact in impacts:
		var moved: Dictionary = impact.duplicate()
		moved["pos"] = (impact["pos"] as Vector2).rotated(angle)
		moved["inward"] = (impact["inward"] as Vector2).rotated(angle)
		out.append(moved)
	return out


## `impacts` moved by `by`: from the shoulders' frame to the character's, once the shoulders lunge.
static func _shifted(impacts: Array, by: Vector2) -> Array:
	if by == Vector2.ZERO:
		return impacts
	var out := []
	for impact in impacts:
		var moved: Dictionary = impact.duplicate()
		moved["pos"] = (impact["pos"] as Vector2) + by
		out.append(moved)
	return out


## The body `impacts` whose shot passed through a part — a circle of `radius` at `center` on the
## shot's path before it struck the body — re-seated where the shot entered the part, in its
## frame, with the dent scaled down to the part's size.
func _through(impacts: Array, center: Vector2, radius: float) -> Array:
	var out := []
	var shrink := radius / float(_character.radius)
	for impact in impacts:
		var p: Vector2 = impact["pos"] - center
		var d: Vector2 = impact["inward"]
		var b := p.dot(d)
		var disc := b * b - (p.length_squared() - radius * radius)
		if disc < 0.0:
			continue  # The shot's line misses the part.
		var t := -b - sqrt(disc)  # Entry along the shot, relative to where it struck the body.
		if t > 0.0:
			continue  # The part lies past the body contact: the body stopped the shot first.
		var seated: Dictionary = impact.duplicate()
		seated["pos"] = p + d * t
		seated["depth"] = float(impact["depth"]) * shrink
		out.append(seated)
	return out


# --- Limbs, shadow and the fallen body --------------------------------------------------
# Limbs are tapered capsules between 3D joints, drawn the same from the standing rig or the fallen
# ragdoll. Once dead the body is the ragdoll's: each part is drawn from its 3D points seen from
# above, the lowest first, so a standing body hides its legs under the shoulders and a toppling one
# reveals them, with the trunk a loft of cross-sections, so every part foreshortens and rounds off
# naturally as it tips toward or away from the camera.


## The shadow layer: a CanvasGroup behind the body carrying the shadow's alpha, around the node
## the body's shadow draws on (opaque, so overlapping parts merge into one shade).
func _build_shadow() -> void:
	var group := CanvasGroup.new()
	group.show_behind_parent = true
	group.self_modulate = Color(1.0, 1.0, 1.0, ArtConfig.drop_shadow_alpha)
	add_child(group)
	_shadow = Node2D.new()
	_shadow_meshes = BodyMeshes.new(_shadow)
	group.add_child(_shadow)
	_shadow.draw.connect(_draw_body_shadow)


## The body's floor shadow, standing or fallen.
func _draw_body_shadow() -> void:
	_shadow_meshes.begin()
	var rd = _character.ragdoll
	if rd != null:
		_draw_fallen_shadow(rd)
	elif draws_laid_out():
		_draw_fallen_shadow(_rig if _rig != null else _character.rig())
	else:
		_draw_standing_shadow()


## Every part of the fallen body, lowest first. A living body bent over draws its own head
## (`with_head` off) over the weapon and the hands; `before_trunk` draws the weapon just under the
## trunk.
func _draw_fallen(rd: RefCounted, with_head := true, before_trunk := Callable()) -> void:
	for part in _stack(_fallen_parts(rd)):
		match part["kind"]:
			"chain":
				_draw_chain(part)
			"hand":
				_draw_fallen_hand(part)
			"head":
				if with_head:
					_draw_fallen_head(part)
			"trunk":
				if before_trunk.is_valid():
					before_trunk.call()
				_draw_trunk(rd)
				if before_trunk.is_valid():
					draw_order.append(&"torso")


## `parts` lowest first. The order carries over from the last frame and a pair swaps only once their
## heights differ by more than `STACK_BAND`, so a limb lying across the trunk (their heights
## jittering around each other) stays on one side instead of flickering between over and under.
func _stack(parts: Array) -> Array:
	var rank := {}
	for i in _fallen_order.size():
		rank[_fallen_order[i]] = i
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return rank.get(a["key"], 99) < rank.get(b["key"], 99))
	for i in range(1, parts.size()):
		var j := i
		while (j > 0
				and (parts[j - 1]["height"] as float) - (parts[j]["height"] as float) > STACK_BAND):
			var below = parts[j]
			parts[j] = parts[j - 1]
			parts[j - 1] = below
			j -= 1
	_fallen_order.clear()
	for part in parts:
		_fallen_order.append(part["key"])
	return parts


## The fallen body's floor shadow: each part's silhouette with every point shifted away from the
## light by its height, so the shadow closes in under the body as it lands.
func _draw_fallen_shadow(rd: RefCounted) -> void:
	var shift := _shadow_shift()
	var fills := FillBatch.new(_shadow)
	for part in _fallen_parts(rd):
		match part["kind"]:
			"chain":
				_draw_limb_shadow(part, shift, fills)
			"hand":
				fills.circle(_cast(part["at"], shift), _hands.hand_radius, Color.BLACK)
			"head":
				fills.circle(
					_cast(part["at"], shift),
					CharacterConfig.ragdoll_head_radius * _character.radius,
					Color.BLACK,
				)
	# The trunk's slices, each its own polygon: the shadow group flattens overlapping black into one
	# shade, so they render as the one outline the body draws, without the union that outline costs.
	for hull in _trunk_hulls(rd, shift):
		fills.fill(hull, Color.BLACK)
	fills.flush()  # All one black: the shadow group shows what any part covers, whatever the order.


## The fallen body's parts as dicts with their `kind` and mean `height`: limb chains (arms, legs
## with their shoes, the neck), fists, the head and the trunk.
func _fallen_parts(rd: RefCounted) -> Array:
	var r: float = _character.radius
	var parts := []
	var limbs := _limbs(rd)
	for i in 2:
		parts.append(_keyed(limbs[2 + i], "arm%d" % i))
		parts.append(_keyed(limbs[i], "leg%d" % i))
		var elbow: Vector3 = rd.point(Rig.ELBOW[i])
		var hand: Vector3 = rd.point(Rig.HAND[i])
		parts.append({
			"kind": "hand",
			"at": hand,
			"height": hand.z + 0.5,
			"key": "hand%d" % i,
			"along": hand - elbow,
			"side": i,
		})
	var head: Vector3 = rd.point(Rig.HEAD)
	var chest: Vector3 = rd.point(Rig.CHEST)
	var neck := CharacterConfig.body_neck_width
	var neck_length := (CharacterConfig.body_head_height - CharacterConfig.body_shoulder_height) * r
	var neck_seg := _painted(_seg(chest, head, neck, neck, neck_length), _skin)
	parts.append(_keyed(_chain([neck_seg]), "neck"))
	parts.append(_head_part(rd))
	parts.append({
		"kind": "trunk",
		"key": "trunk",
		"height": (chest.z + rd.point(Rig.PELVIS).z) * 0.5,
	})
	return parts


## The head as a fallen-body part: where it is, the way it faces and the neck it sits on.
func _head_part(rd: RefCounted) -> Dictionary:
	var head: Vector3 = rd.point(Rig.HEAD)
	return { "kind": "head", "key": "head", "at": head, "height": head.z, "face": rd.face(),
		"neck": rd.point(Rig.CHEST) - head }


## `part` tagged with the stable `key` its draw order is remembered by.
func _keyed(part: Dictionary, key: String) -> Dictionary:
	part["key"] = key
	return part


## The limb chains from the joints of `j` (the rig, or the ragdoll), legs then arms:
## `[leg 0, leg 1, arm 0, arm 1]`. The body's draw and its shadow's ask for the same chains, so they
## are built once for both: kept for the same joints within one physics frame, and dropped at every
## `_process` (before the draws; the ragdoll may have stepped since an earlier ask in the same
## frame) and when the look changes (`_dress`).
func _limbs(j: RefCounted) -> Array:
	var frame := Engine.get_physics_frames()
	if not is_same(j, _limbs_of) or frame != _limbs_frame:
		_limb_chains = [_leg_chain(j, 0), _leg_chain(j, 1), _arm_chain(j, 0), _arm_chain(j, 1)]
		_limbs_of = j
		_limbs_frame = frame
	return _limb_chains


## Side `i`'s arm as a limb chain from the joints of `j` (the rig or the ragdoll): the upper arm to
## the elbow, the forearm to the center of the fist, each a sleeve, bare skin or chrome
## (`_arm_parts`).
func _arm_chain(j: RefCounted, i: int) -> Dictionary:
	var r: float = _character.radius
	var arm: Array = CharacterConfig.body_arm_widths
	var shoulder: Vector3 = j.point(Rig.SHOULDER[i])
	var elbow: Vector3 = j.point(Rig.ELBOW[i])
	var hand: Vector3 = j.point(Rig.HAND[i])
	var upper: Dictionary = _arm_parts[i]["upper"]
	var fore: Dictionary = _arm_parts[i]["fore"]
	return _chain([
		_painted(
			_seg(shoulder, elbow, arm[0], arm[1], CharacterConfig.body_upper_arm * r),
			upper["color"],
			upper["opts"],
		),
		_painted(
			_seg(elbow, hand, arm[1], arm[2], CharacterConfig.body_forearm * r),
			fore["color"],
			fore["opts"],
		),
	])


## Side `i`'s leg as a limb chain from the joints of `j`: the thigh, the shin in two parts (the
## calf is wider than the ankle, and in chrome below the knee on a chrome leg) and the shoe along
## the way the foot points; in boots the shin's lower part is the boot's shaft and the boot is a
## little wider.
func _leg_chain(j: RefCounted, i: int) -> Dictionary:
	var r: float = _character.radius
	var leg: Array = CharacterConfig.body_leg_widths
	var knee: Vector3 = j.point(Rig.KNEE[i])
	var ankle: Vector3 = j.point(Rig.ANKLE[i])
	var calf := knee.lerp(ankle, 0.35)
	var shin := CharacterConfig.body_shin * r
	var opts: Dictionary = _leg_opts[i]
	var segs := [
		_painted(
			_seg(j.point(Rig.HIP[i]), knee, leg[0], leg[1], CharacterConfig.body_thigh * r),
			_pants,
			opts["thigh"],
		),
		_painted(_seg(knee, calf, leg[1], leg[2], shin * 0.35), _pants, opts["knee"]),
	]
	if _boots:
		_add_boot(segs, j, i, calf)
	else:
		segs.append(_painted(
			_seg(calf, ankle, leg[2], leg[3], shin * 0.65), _shin_colour(i), opts["shin"],
		))
		segs.append(_foot_seg(j, i, 0.0))
	return _chain(segs)


## Side `i`'s boot added to its leg's `segs` from the joints of `j`: the shin from the `calf` to the
## boot's top, the boot's shaft down to the ankle, a little wider, and the boot.
func _add_boot(segs: Array, j: RefCounted, i: int, calf: Vector3) -> void:
	var leg: Array = CharacterConfig.body_leg_widths
	var knee: Vector3 = j.point(Rig.KNEE[i])
	var ankle: Vector3 = j.point(Rig.ANKLE[i])
	var r: float = _character.radius
	var shin := CharacterConfig.body_shin * r
	var opts: Dictionary = _leg_opts[i]
	var top := knee.lerp(ankle, BOOT_TOP)
	var top_width: float = lerpf(leg[2], leg[3], (BOOT_TOP - 0.35) / 0.65) + BOOT_GROW
	segs.append(_painted(
		_seg(calf, top, leg[2], top_width - BOOT_GROW, shin * (BOOT_TOP - 0.35)),
		_shin_colour(i),
		opts["shin"],
	))
	segs.append(_painted(
		_seg(top, ankle, top_width, leg[3] + BOOT_GROW, shin * (1.0 - BOOT_TOP)),
		_shoes,
		opts["shaft"],
	))
	segs.append(_foot_seg(j, i, BOOT_GROW))


## Side `i`'s shoe (`grow` body radii wider: a boot) along the way the foot of `j` points, a
## quarter of it behind the ankle.
func _foot_seg(j: RefCounted, i: int, grow: float) -> Dictionary:
	var shoe: Array = CharacterConfig.body_shoe_widths
	var ankle: Vector3 = j.point(Rig.ANKLE[i])
	var toes: Vector3 = j.toes(i)
	var r: float = _character.radius
	var foot := CharacterConfig.body_foot * r
	var heel := ankle - toes * foot * 0.25
	var tip := ankle + toes * foot * 0.75
	return _painted(
		_seg(heel, tip, shoe[0] + grow, shoe[1] + grow, foot), _shoes, _leg_opts[i]["foot"],
	)


## Side `i`'s shin colour: chrome on a chrome leg, else the trousers.
func _shin_colour(i: int) -> Color:
	return _chrome if _chrome_shin[i] else _pants


## One tapered limb segment from `a` to `b` (3D): its widths at each end in body radii and the true
## `length` (px) its art is painted at (`_painted` gives it its colour and options).
func _seg(a: Vector3, b: Vector3, width_a: float, width_b: float, length: float) -> Dictionary:
	var r: float = _character.radius
	return { "a": a, "b": b, "ra": width_a * r * 0.5, "rb": width_b * r * 0.5, "length": length }


## Segment `seg` painted in `color` with its painter options `opts` (its `material` among them).
static func _painted(seg: Dictionary, color: Color, opts: Dictionary = _PLAIN) -> Dictionary:
	seg["color"] = color
	seg["opts"] = opts
	return seg


## A limb chain: its segments, sorted as one part by their mean height.
func _chain(segs: Array) -> Dictionary:
	var height := 0.0
	for seg in segs:
		height += ((seg["a"] as Vector3).z + (seg["b"] as Vector3).z) * 0.5
	return { "kind": "chain", "segs": segs, "height": height / segs.size() }


## A limb chain: every segment first a pixel wider in its outline tone, then every fill over them
## (lowest first), so the joints run together under one continuous outline.
func _draw_chain(chain: Dictionary) -> void:
	var outlines := FillBatch.new(self)
	# The segments by mean height, lowest first; a tie keeps the chain's order.
	var order: Array = []
	var heights: Array[float] = []
	for seg in chain["segs"]:
		_outline_seg(outlines, seg)
		var height := (seg["a"] as Vector3).z + (seg["b"] as Vector3).z
		var at := order.size()
		while at > 0 and height < heights[at - 1]:
			at -= 1
		order.insert(at, seg)
		heights.insert(at, height)
	outlines.flush()
	for seg in order:
		_draw_segment(seg)


## Segment `seg`'s capsule a pixel wider all round added to `outlines`, in its colour's outline tone
## (PixelCanvas.tones).
static func _outline_seg(outlines: FillBatch, seg: Dictionary) -> void:
	var a3: Vector3 = seg["a"]
	var b3: Vector3 = seg["b"]
	var a := Vector2(a3.x, a3.y)
	var b := Vector2(b3.x, b3.y)
	var ra: float = seg["ra"] + 1.0
	var rb: float = seg["rb"] + 1.0
	var tone := (seg["color"] as Color).darkened(ArtConfig.tone_outline)
	_fill_capsule(outlines, _capsule(a, b, ra, rb), _convex(a, b, ra, rb), tone)


## One limb segment's art (a shaded strip from limb_painter.gd) mapped onto its tapered capsule:
## across the strip runs across the limb, along it from end to end.
func _draw_segment(seg: Dictionary) -> void:
	var a := _flat(seg["a"])
	var b := _flat(seg["b"])
	var ra: float = seg["ra"]
	var rb: float = seg["rb"]
	var span := a.distance_to(b)
	var dir := (b - a) / span if span > 0.01 else Vector2.DOWN
	var widest := maxf(ra, rb)
	var tex := PixelArt.render_turned(
		LimbPainter,
		Vector2(roundf(widest * 2.0), roundf(float(seg["length"]) + ra + rb)),
		seg["color"],
		PixelArt.snap_angle(dir.angle() - PI * 0.5),
		seg["opts"],
	)
	_art.append(tex)
	var poly := _capsule(a, b, ra, rb)
	_meshes.draw(
		poly, _strip_uvs(a, dir, span, ra, rb) * poly, tex, Color.WHITE,
		Rect2(a.min(b), (b - a).abs()).grow(widest),
	)


## The transform from canvas px to a strip's uvs on the capsule from `a` (radius `ra`) `span` px
## along `dir` to its other end (`rb`): across the strip, the offset from the axis over the strip's
## width; along it, from `ra` behind `a` over the whole length.
static func _strip_uvs(a: Vector2, dir: Vector2, span: float, ra: float, rb: float) -> Transform2D:
	var across := dir.orthogonal() / (maxf(ra, rb) * 2.0)
	var along := dir / (span + ra + rb)
	return Transform2D(Vector2(across.x, along.x), Vector2(across.y, along.y),
		Vector2(0.5 - across.dot(a), (ra - dir.dot(a)) / (span + ra + rb)))


## A tapered capsule outline from `a` (radius `ra`) to `b` (radius `rb`): a round cap behind each
## end joined by straight sides; a circle when the ends meet (a limb pointing at the camera).
static func _capsule(a: Vector2, b: Vector2, ra: float, rb: float) -> PackedVector2Array:
	var span := a.distance_to(b)
	if span < 0.5:
		var rad := maxf(ra, rb)
		return Transform2D(0.0, Vector2(rad, rad), 0.0, a) * _CAP_ROUND
	var base := (b - a).angle()
	var out := Transform2D(base, Vector2(ra, ra), 0.0, a) * _CAP_BEHIND
	out.append_array(Transform2D(base, Vector2(rb, rb), 0.0, b) * _CAP_AHEAD)
	return out


## Add the capsule `poly` (`_capsule(a, b, ra, rb)`) to `fills` (a `FillBatch` or a
## `BodyMeshes.Solid`) in `color`: as a fan without being cut when it is `convex` (`_convex`), else
## cut as the engine cuts it.
static func _fill_capsule(
	fills: RefCounted,
	poly: PackedVector2Array,
	convex: bool,
	color: Color,
) -> void:
	if convex:
		fills.fill_convex(poly, color)
	else:
		fills.fill(poly, color)


## Whether the capsule from `a` (radius `ra`) to `b` (`rb`) is convex: one whose ends' radii differ
## by less than `CAP_CONVEX` of its length (each cap ends half a step, 15°, short of its side, which
## leans by `atan(|ra - rb| / span)`), or a circle.
static func _convex(a: Vector2, b: Vector2, ra: float, rb: float) -> bool:
	var span := a.distance_to(b)
	return span < 0.5 or absf(ra - rb) < span * CAP_CONVEX


## `count` unit vectors round the circle, `k` at angle `TAU * k / count`.
static func _ring(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in count:
		out.append(Vector2.from_angle(TAU * k / count))
	return out


## `count` unit vectors from angle `from`, `step` apart.
static func _arc(from: float, step: float, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in count:
		out.append(Vector2.from_angle(from + step * k))
	return out


## A 3D point's place on the floor plane, seen from above.
static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y)


## The trunk's cross-section at spine fraction `t` (0 = hip joints, 1 = shoulder joints) as
## Vector2(half-width, half-depth) in body radii, eased between the configured sections so the
## outline curves; past either end it rounds off in a dome.
static func _section_at(t: float) -> Vector2:
	var sections: Array = CharacterConfig.ragdoll_trunk_sections
	var first: Vector3 = sections[0]
	var last: Vector3 = sections[sections.size() - 1]
	if t < first.x:
		return Vector2(first.y, first.z) * _dome((first.x - t) / DOME_BOTTOM)
	if t > last.x:
		return Vector2(last.y, last.z) * _dome((t - last.x) / DOME_TOP)
	for k in range(1, sections.size()):
		var hi: Vector3 = sections[k]
		if t <= hi.x:
			var lo: Vector3 = sections[k - 1]
			var w := smoothstep(0.0, 1.0, (t - lo.x) / maxf(hi.x - lo.x, 0.001))
			return Vector2(lerpf(lo.y, hi.y, w), lerpf(lo.z, hi.z, w))
	return Vector2(last.y, last.z)


## A dome's width `s` of the way (0..1) from its base to its tip.
static func _dome(s: float) -> float:
	return sqrt(maxf(1.0 - 0.85 * s * s, 0.0))


## The spine fractions the trunk's outline is lofted through: the domes under the hips and over the
## shoulders, and evenly between them.
static func _trunk_steps() -> PackedFloat32Array:
	var sections: Array = CharacterConfig.ragdoll_trunk_sections
	var t0: float = (sections[0] as Vector3).x
	var t1: float = (sections[sections.size() - 1] as Vector3).x
	var out := PackedFloat32Array()
	for k in range(DOME_STEPS, 0, -1):
		out.append(t0 - DOME_BOTTOM * k / DOME_STEPS)
	for k in TRUNK_STEPS + 1:
		out.append(lerpf(t0, t1, float(k) / TRUNK_STEPS))
	for k in range(1, DOME_STEPS + 1):
		out.append(t1 + DOME_TOP * k / DOME_STEPS)
	return out


## The trunk's outline seen from above, each point shifted by `shift` per px of its height (zero: as
## drawn; `_shadow_shift`: on the floor shadow): the union of the hulls of each pair of
## neighbouring cross-sections (ellipses across the spine, eased between
## CharacterConfig.ragdoll_trunk_sections and domed at both ends), so it is waisted and rounded from
## any side and shrinks to the shoulders seen from above.
func _trunk_outline(rd: RefCounted, shift := Vector2.ZERO) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var hulls := _trunk_hulls(rd, shift)
	for hull in hulls:
		if outline.is_empty():
			outline = hull
			continue
		var merged := Geometry2D.merge_polygons(outline, hull)
		if merged.size() == 1:
			# One piece (most merges): it is the largest and the only outer one, whatever its area
			# (a union of slices has some).
			outline = merged[0] if merged[0].size() >= 3 else outline
			continue
		var best := PackedVector2Array()
		var best_area := 0.0
		var outer := 0
		for poly in merged:
			var area := _area(poly)
			if area > best_area:
				best = poly
				best_area = area
			if not Geometry2D.is_polygon_clockwise(poly) and area > PIECE_MIN_AREA:
				outer += 1
		if outer > 1:
			# The union came apart (two outer pieces): keep both slices in one hull rather than
			# drop the body so far.
			outline = _open(Geometry2D.convex_hull(outline + hull))
		else:
			# The union's outer boundary is its largest piece (any others would be holes).
			outline = best if best.size() >= 3 else outline
	if Geometry2D.triangulate_polygon(outline).is_empty():
		var everything := PackedVector2Array()
		for hull in hulls:
			everything.append_array(hull)
		outline = _open(Geometry2D.convex_hull(everything))
	return outline


## The trunk's slices seen from above, shifted by `shift` per px of height (as `_trunk_outline`):
## the hull of each pair of neighbouring cross-sections (ellipses across the spine, eased between
## CharacterConfig.ragdoll_trunk_sections and domed at both ends), each grown by `HULL_OVERLAP`.
## Their union is the trunk's outline (`_trunk_outline`); the shadow draws them as they are.
func _trunk_hulls(rd: RefCounted, shift := Vector2.ZERO) -> Array[PackedVector2Array]:
	var r: float = _character.radius
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(Rig.PELVIS)
	var spine: float = (rd.point(Rig.CHEST) - pelvis).length()
	var rings := []
	for t in _trunk_steps():
		var centre: Vector3 = pelvis + basis.y * t * spine
		var half := _section_at(t) * r
		var ring := PackedVector2Array()
		for around in _SECTION_RING:
			ring.append(
				_cast(centre + basis.x * around.x * half.x + basis.z * around.y * half.y, shift),
			)
		rings.append(ring)
	var hulls: Array[PackedVector2Array] = []
	for k in range(1, rings.size()):
		hulls.append(_grown(_open(Geometry2D.convex_hull(rings[k - 1] + rings[k]))))
	return hulls


## `poly` grown by `HULL_OVERLAP`, so neighbouring slices of the trunk overlap in area. They share a
## ring, which seen edge-on is a line, and slices touching along a line can come out of the union as
## separate pieces.
static func _grown(poly: PackedVector2Array) -> PackedVector2Array:
	var grown := Geometry2D.offset_polygon(poly, HULL_OVERLAP, Geometry2D.JOIN_MITER)
	return grown[0] if grown.size() == 1 else poly


## The area enclosed by `poly`, whichever way it winds.
static func _area(poly: PackedVector2Array) -> float:
	var twice := 0.0
	for k in poly.size():
		twice += poly[k].cross(poly[(k + 1) % poly.size()])
	return absf(twice) * 0.5


## `poly` without a closing point that repeats its first.
static func _open(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() > 1 and poly[0].is_equal_approx(poly[poly.size() - 1]):
		poly.remove_at(poly.size() - 1)
	return poly


## The trunk: a shirt-colored underfill of its outline, the art of the sides turned to the camera
## mapped across it (`_trunk_faces`: the chest, the back or a flank, with the shoulders' top over it
## when that is the side most turned up), a 1 px outline, then the wounds on whatever skin faces up.
func _draw_trunk(rd: RefCounted) -> void:
	var outline := _trunk_outline(rd)
	if outline.size() < 3:
		return
	draw_colored_polygon(outline, _shirt)
	for face in _trunk_faces(rd):
		var ax: Vector2 = face["x"]
		var ay: Vector2 = face["y"]
		var size: Vector2 = face["size"]
		var det := ax.x * ay.y - ax.y * ay.x
		if absf(det) <= 0.0001:
			continue
		var uvs := PackedVector2Array()
		for p in outline:
			var rel: Vector2 = p - face["center"]
			var u := (rel.x * ay.y - rel.y * ay.x) / det
			var v := (ax.x * rel.y - ax.y * rel.x) / det
			uvs.append(Vector2(u / size.x + 0.5, v / size.y + 0.5))
		_meshes.draw(outline, uvs, face["texture"])
		_art.append(face["texture"])
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, PixelCanvas.tones(_shirt).outline, 1.0)
	_draw_wounds(rd)


## The trunk's sides to map across its outline, lowest first, each as its `texture`, its `center`
## and the screen vectors its art's x and y run along (per px) over its `size`: the side most turned
## to the camera of the chest, the back and a flank (the torso art, a full strip that covers the
## outline), and over it the shoulders' top when that is turned up more still (a body bent over in a
## crouch, or upright as it starts to fall). The shoulders' art covers only the shoulders, so drawn
## alone it would leave the rest of a bent back (and whatever is worn on it) bare shirt.
func _trunk_faces(rd: RefCounted) -> Array:
	var r: float = _character.radius
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(Rig.PELVIS)
	var spine: float = (rd.point(Rig.CHEST) - pelvis).length()
	var sections: Array = CharacterConfig.ragdoll_trunk_sections
	var bottom: float = ((sections[0] as Vector3).x - DOME_BOTTOM) * spine
	var top: float = ((sections[sections.size() - 1] as Vector3).x + DOME_TOP) * spine
	var mid: Vector3 = pelvis + basis.y * (bottom + top) * 0.5
	var faces := [
		{
			"kind": "top", "score": basis.y.z, "centre": pelvis + basis.y * top, "x": basis.x,
			"y": basis.z, "size": Vector2(2.0 * r, 2.0 * r),
		},
	]
	faces.append_array(_trunk_sides(basis, mid, top - bottom))
	var side_on: Dictionary = faces[1] if faces[1]["score"] >= faces[2]["score"] else faces[2]
	if faces[0]["score"] > side_on["score"]:
		return [_face_art(side_on), _face_art(faces[0])]
	return [_face_art(side_on)]


## The trunk's chest or back (whichever faces up) and a flank, as `_trunk_faces` scores them: turned
## by `basis`, about the trunk's `mid` point, `length` px along the spine.
func _trunk_sides(basis: Basis, mid: Vector3, length: float) -> Array:
	var r: float = _character.radius
	var depth := CharacterConfig.art_shoulder_depth * r
	var side := signf(basis.x.z) if basis.x.z != 0.0 else 1.0
	var facing := signf(basis.z.z) if basis.z.z != 0.0 else 1.0
	return [
		{
			"kind": "front" if facing > 0.0 else "back", "score": absf(basis.z.z),
			"centre": mid + basis.z * depth * facing, "x": basis.x * facing, "y": -basis.y,
			"size": Vector2(2.0 * r, length),
		},
		{
			"kind": "side", "score": absf(basis.x.z), "centre": mid + basis.x * r * side,
			"x": basis.z * -side, "y": -basis.y, "size": Vector2(2.0 * depth, length),
		},
	]


## One trunk side (`face`, from `_trunk_faces`) as the art to map: its texture, centre and screen
## axes.
func _face_art(face: Dictionary) -> Dictionary:
	var x3: Vector3 = face["x"]
	var y3: Vector3 = face["y"]
	var ax := _flat(x3)
	var ay := _flat(y3)
	var size: Vector2 = face["size"]
	var angle := ay.angle() - PI * 0.5 if ay.length() > 0.05 else ax.angle()  # The art's turn.
	# The art is asked for at whole pixels, as the limbs' is (`_draw_segment`): the spine's length
	# changes a little every frame as the ragdoll flexes, and a size that is never the same twice
	# paints (and caches) a new texture every frame.
	var art_size := Vector2(roundf(size.x), roundf(size.y))
	var tex: Texture2D
	if face["kind"] == "top":
		tex = PixelArt.render_turned(
			BodyPainter,
			art_size,
			_shirt,
			PixelArt.snap_angle(angle),
			_shoulder_opts,
		)
	else:
		tex = PixelArt.render_turned(
			TorsoPainter, art_size, _shirt, PixelArt.snap_angle(angle), _torso_opts[face["kind"]],
		)
	return { "texture": tex, "center": _flat(face["centre"]), "x": ax, "y": ay, "size": size }


## The shots the body took while alive, as wounds on its fallen trunk: each sits around the body
## where it struck (its angle in the shoulders' frame) at a height seeded per wound between waist
## and chest, and shows only while that patch of skin faces the camera — the chest's wounds on a
## body lying on its back, the back's on one lying face down.
func _draw_wounds(rd: RefCounted) -> void:
	var deformable = _character._deformable
	if deformable == null:
		return
	var basis: Basis = rd.torso()
	var pelvis: Vector3 = rd.point(Rig.PELVIS)
	var spine: float = (rd.point(Rig.CHEST) - pelvis).length()
	var wounds := []
	for impact in deformable.impacts:
		var wound := _wound(impact, basis, pelvis, spine)
		if not wound.is_empty():
			wounds.append(wound)
	Deformation.draw_marks(
		self, wounds, CharacterConfig.flesh_crack_color, CharacterConfig.flesh_hole_color,
		CharacterConfig.flesh_scorch_color,
	)


## The wound `impact` left on the fallen trunk (turned by `basis`, up its `spine` px from the
## `pelvis`): around the body where it struck, at its seeded height, its depth by how squarely that
## patch faces the camera; {} while it faces away.
func _wound(impact: Dictionary, basis: Basis, pelvis: Vector3, spine: float) -> Dictionary:
	var pos: Vector2 = impact["pos"]
	if pos.length() < 0.001:
		return {}
	# Recorded with the body facing +x: its right is −y, its front +x.
	var around := Vector2(-pos.y, pos.x).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(impact["seed"])
	var t := rng.randf_range(0.35, 0.9)
	var r: float = _character.radius
	var half := _section_at(t) * r
	var on := _on_section(around, half)
	var skin: Vector3 = pelvis + basis.y * t * spine + basis.x * on.x + basis.z * on.y
	var normal: Vector3 = (basis.x * on.x / (half.x * half.x)
			+ basis.z * on.y / (half.y * half.y)).normalized()
	if normal.z < WOUND_MIN_FACING:
		return {}
	var wound: Dictionary = impact.duplicate()
	wound["pos"] = _flat(skin)
	wound["inward"] = Vector2.ZERO
	wound["depth"] = float(impact["depth"]) * normal.z
	return wound


## Where the way `around` (unit, across the spine) meets the edge of a cross-section of half-width
## and half-depth `half`.
static func _on_section(around: Vector2, half: Vector2) -> Vector2:
	var reach := 1.0 / sqrt(pow(around.x / half.x, 2.0) + pow(around.y / half.y, 2.0))
	return around * reach


## A fallen fist, its knuckles along the forearm.
func _draw_fallen_hand(hand: Dictionary) -> void:
	var at: Vector3 = hand["at"]
	var along: Vector3 = hand["along"]
	var flat := _flat(along)
	var angle := flat.angle() - PI * 0.5 if flat.length() > 0.5 else 0.0
	var diameter: float = _hands.hand_radius * 2.0 + 2.0
	var size := Vector2(diameter, diameter)
	var part: Dictionary = _hand_parts[hand["side"]]
	var tex := PixelArt.render_turned(
		HandPainter,
		size,
		part["color"],
		PixelArt.snap_angle(angle),
		part["opts"],
	)
	_art.append(tex)
	draw_set_transform(_flat(at), angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The fallen head, its art's front turned the way the face looks; a face turned up or down shows
## its front toward the neck, the crown away from the body.
func _draw_fallen_head(head: Dictionary) -> void:
	var px := ArtConfig.pixel_size
	var side := (float(HeadPainter.canvas_for(HeadPainter.radius_for(roundi(_character.radius * 2.0
			/ px)))) * px)
	var size := Vector2(side, side)
	var face: Vector3 = head["face"]
	var neck: Vector3 = head["neck"]
	var look := _flat(face) + _flat(neck).normalized() * absf(face.z)
	var angle := look.angle() - PI * 0.5 if look.length() > 0.01 else 0.0
	var tex := PixelArt.render_turned(
		HeadPainter,
		size,
		_skin,
		PixelArt.snap_angle(angle),
		_head_opts,
	)
	_art.append(tex)
	draw_set_transform(_flat(head["at"]), angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
