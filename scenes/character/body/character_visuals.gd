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
## `look_seed`, `rank`; `docs/outfits.md`, styles) and what it wears drawn in that style (`dress`,
## `body_dress.gd`, through `character_style.gd`): the headwear, the shirt and its sleeves, a vest
## and its plates' wear, the pants and the footwear, and its own skin, hair, gloves, pack and
## implants.

const BodyPainter = preload("res://scenes/character/body/art/body_painter.gd")
const HeadPainter = preload("res://scenes/character/body/art/head_painter.gd")
const HandPainter = preload("res://scenes/character/body/art/hand_painter.gd")
const TorsoPainter = preload("res://scenes/character/body/art/torso_painter.gd")
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
## Points sampled around each trunk cross-section.
const SECTION_POINTS := 16
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

## The unit ring a trunk cross-section is sampled on (`_trunk_hulls`): point `k` at angle
## `TAU * k / SECTION_POINTS`.
static var _SECTION_RING := _ring(SECTION_POINTS)

## The textured parts drawn on the body, as meshes kept from draw to draw.
var meshes: BodyMeshes
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
var art: Array[Texture2D] = []
## How the round part being drawn is drawn: one look, refilled for each part (`_round_look`).
var _look := ShapeLook.new()
## What each part is drawn in (`body_dress.gd`).
var dress: BodyDress
## The body's floor shadow (`body_shadow.gd`).
var shadow: BodyShadow
## The limbs (`body_limbs.gd`).
var limbs: BodyLimbs

## Character — body radius, pose, rig, held item.
@onready var _character := get_parent()
## Sibling — hand positions / size.
@onready var _hands := $"../Hands"


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	meshes = BodyMeshes.new(self)
	shadow = BodyShadow.new(self, _character, _hands)
	shadow.node.draw.connect(_draw_shadow)
	dress = BodyDress.new()
	dress.refresh(_character)
	limbs = BodyLimbs.new(self, _character, dress)


func _process(_delta: float) -> void:
	limbs.drop()  # The limb chains are shared by this frame's two draws only (`limbs.chains`).
	if not _in_view():
		if not _offscreen:
			_offscreen = true
			# Whatever changes off screen, the first frame back repaints.
			_redraw_key = PackedInt32Array()
		return
	_offscreen = false
	var ragdoll = _character.ragdoll
	if dress.refresh(_character):
		_settled_drawn = false  # A body at rest repaints what it now wears.
	if ragdoll == null:
		_rig = _character.rig()
		var key := _redraw_key_of(_rig)
		if key != _redraw_key:
			_redraw_key = key
			queue_redraw()
			shadow.node.queue_redraw()
		return
	if _settled_drawn:
		return
	_settled_drawn = ragdoll.is_settled()
	queue_redraw()
	shadow.node.queue_redraw()


func _draw() -> void:
	art.clear()
	meshes.begin()
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


## The body's floor shadow (the shadow node's draw), standing or fallen: standing, the shoulders'
## silhouette first, then the rest of the body.
func _draw_shadow() -> void:
	shadow.meshes.begin()
	var rd = _character.ragdoll
	if rd != null:
		shadow.draw_fallen(rd)
	elif draws_laid_out():
		shadow.draw_fallen(_rig if _rig != null else _character.rig())
	else:
		var rig: Rig = _rig if _rig != null else _character.rig()
		var shift := shadow.shift()
		shadow.draw_standing(rig, shift, _draw_shoulders_shadow(rig, shift))


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

	for chain in limbs.chains(rig):  # The legs, then the arms.
		limbs.draw_chain(chain)
	# The weapon goes under the torso: its butt is tucked behind the shoulder, the barrel shows
	# beyond.
	if item:
		item.draw_weapon(self, _character)
		draw_order.append(&"weapon")
	# A hand hanging at the side (below HAND_OVER_HEIGHT) is lower than the shoulders, so they cover
	# it.
	var hung: Array[int] = []
	for hand in 2:
		if pose.arms.grip_height(hand) < HAND_OVER_HEIGHT:
			hung.append(hand)
			_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, placed, damage_total)
	_draw_shoulders(pose, lunge, impacts, damage_total)
	for hand in 2:
		if not hung.has(hand) and pose.arms.grip_height(hand) < HAND_ON_FACE_HEIGHT:
			_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, placed, damage_total)
	draw_order.append(&"hands")
	_draw_head(pose, rig, placed, damage_total)  # The highest part: over the gun and the fists.
	draw_order.append(&"head")
	_draw_face_hands(pose, placed, damage_total)
	# Wound marks over everything, so a hit hand shows its wound: dark-red holes and cracks that
	# read as bloody gashes (config-driven).
	Deformation.draw_marks(self, placed, CharacterArtConfig.flesh_crack_color,
		CharacterArtConfig.flesh_hole_color, CharacterArtConfig.flesh_scorch_color)


## The shoulders at the `lunge`: the art through the flesh silhouette deformed by the shots
## (`impacts`, in the shoulders' frame: dents, and darkening by `damage_total`).
func _draw_shoulders(pose: Pose, lunge: Vector2, impacts: Array, damage_total: float) -> void:
	var torso: float = pose.torso_angle - PI * 0.5  # Canonical art faces +y.
	var body := _shoulder_art(torso)
	draw_set_transform(lunge, 0.0, Vector2.ONE)
	art.append(body)
	_draw_round(
		_shoulder_size(),
		impacts,
		_round_look(body, torso, damage_total, dress.shirt, CharacterArtConfig.flesh_crack_color),
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
	key.append(dress.look_key)
	return key


## The textures the last draw of the body painted (standing, crouched or fallen), in order: its
## limbs, fists, shoulders or trunk and head (not the held item's). Pixel art is cached by what it
## depicts, so the same drawing gives the same textures.
func drawn_art() -> Array:
	return art.duplicate()


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
		if pose.arms.grip_height(hand) < HAND_ON_FACE_HEIGHT:
			_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, [], 0.0)
	draw_order.append(&"hands")
	_draw_fallen_head(_head_part(rig))  # The highest part: over the gun and the fists.
	draw_order.append(&"head")
	_draw_face_hands(pose, [], 0.0)


## A hand held over the face (a blinded character's palm over its eyes) is drawn over the head;
## `face_hand` joins the draw order when one is.
func _draw_face_hands(pose: Pose, placed: Array, damage_total: float) -> void:
	for hand in 2:
		if pose.arms.grip_height(hand) >= HAND_ON_FACE_HEIGHT:
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
		dress.shirt,
		PixelArt.snap_angle(angle),
		dress.shoulder_opts,
	)


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
	# The shoulders' lunge, shifted from the light.
	var lift := BodyShadow.cast(rig.point(Rig.CHEST), shift)
	shadow.meshes.draw(
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


## The head at the pose's offset and angle, casting its shadow onto the shoulders first (the head
## sits above them, so its silhouette darkens them a few px away from the light).
func _draw_head(pose: Pose, rig: Rig, impacts: Array, damage_total: float) -> void:
	var px := ArtCanvasConfig.pixel_size
	var side := (float(HeadPainter.canvas_for(HeadPainter.radius_for(roundi(_character.radius * 2.0
			/ px)))) * px)
	var size := Vector2(side, side)
	var angle: float = pose.head_angle - PI * 0.5
	var tex := PixelArt.render_turned(
		HeadPainter,
		size,
		dress.skin,
		PixelArt.snap_angle(angle),
		dress.head_opts,
	)
	var at := _rig_xy(rig, Rig.HEAD)  # The pose's offset, plus the neck's pitch in a crouch.
	var toward := -ArtCanvasConfig.light_from.normalized()
	var drop := global_transform.basis_xform_inv(toward).normalized() \
		* ArtCanvasConfig.cast_shadow_px * px
	draw_set_transform(at + drop, angle, Vector2.ONE)
	draw_texture_rect(
		tex,
		Rect2(-size * 0.5, size),
		false,
		Color(0.0, 0.0, 0.0, ArtCanvasConfig.cast_shadow_darken),
	)
	_draw_part(at, size, impacts, _round_look(tex, angle, damage_total, dress.skin, dress.skin))


## A fist at the given hand (0 = right as drawn, 1 = left), turned to `angle`, dented by the shots
## that passed through where it is and darkened like the body.
func _draw_hand(hand: int, angle: float, impacts: Array, damage_total: float) -> void:
	var diameter: float = _hands.hand_radius * 2.0 + 2.0
	var size := Vector2(diameter, diameter)
	var part: Dictionary = dress.hand_parts[hand]
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
	art.append(look.texture)
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
## kept mesh (`meshes`): the polygon and uvs `draw_shape` maps the art onto (`_texture_uvs`), in
## white darkened as it darkens it (`Deformation.darken`). Without meshes (`BodyMeshes.enabled`)
## `draw_shape` draws it.
func _draw_round(size: Vector2, impacts: Array, look: ShapeLook) -> void:
	if not BodyMeshes.enabled:
		Deformation.draw_shape(self, "circle", size, impacts, look)
		return
	var poly := Deformation.shape_polygon("circle", size, impacts)
	if not impacts.is_empty() and not Deformation.is_valid_polygon(poly):
		poly = Deformation.base_ring("circle", size)
	meshes.draw(
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


## Every part of the fallen body, lowest first. A living body bent over draws its own head
## (`with_head` off) over the weapon and the hands; `before_trunk` draws the weapon just under the
## trunk.
func _draw_fallen(rd: RefCounted, with_head := true, before_trunk := Callable()) -> void:
	for part in _stack(_fallen_parts(rd)):
		match part["kind"]:
			"chain":
				limbs.draw_chain(part)
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


## The fallen body's parts as dicts with their `kind` and mean `height`: limb chains (arms, legs
## with their shoes, the neck), fists, the head and the trunk.
func _fallen_parts(rd: RefCounted) -> Array:
	var r: float = _character.radius
	var parts := []
	var chains := limbs.chains(rd)
	for i in 2:
		parts.append(_keyed(chains[2 + i], "arm%d" % i))
		parts.append(_keyed(chains[i], "leg%d" % i))
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
	var neck := CharacterArtConfig.body_neck_width
	var neck_length := (CharacterBodyConfig.head_height - CharacterBodyConfig.shoulder_height) * r
	var neck_seg := BodyLimbs.painted(
		limbs.segment(chest, head, neck, neck, neck_length),
		dress.skin,
	)
	parts.append(_keyed(limbs.chain_of([neck_seg]), "neck"))
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


## `count` unit vectors round the circle, `k` at angle `TAU * k / count`.
static func _ring(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in count:
		out.append(Vector2.from_angle(TAU * k / count))
	return out


## The trunk's cross-section at spine fraction `t` (0 = hip joints, 1 = shoulder joints) as
## Vector2(half-width, half-depth) in body radii, eased between the configured sections so the
## outline curves; past either end it rounds off in a dome.
static func _section_at(t: float) -> Vector2:
	var sections: Array = CharacterArtConfig.ragdoll_trunk_sections
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
	var sections: Array = CharacterArtConfig.ragdoll_trunk_sections
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
## drawn; `BodyShadow.shift`: on the floor shadow): the union of the hulls of each pair of
## neighbouring cross-sections (ellipses across the spine, eased between
## CharacterArtConfig.ragdoll_trunk_sections and domed at both ends), so it is waisted and rounded
## from any side and shrinks to the shoulders seen from above.
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
## CharacterArtConfig.ragdoll_trunk_sections and domed at both ends), each grown by `HULL_OVERLAP`.
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
				BodyShadow.cast(
					centre + basis.x * around.x * half.x + basis.z * around.y * half.y, shift,
				),
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
	draw_colored_polygon(outline, dress.shirt)
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
		meshes.draw(outline, uvs, face["texture"])
		art.append(face["texture"])
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, PixelCanvas.tones(dress.shirt).outline, 1.0)
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
	var sections: Array = CharacterArtConfig.ragdoll_trunk_sections
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
	var depth := CharacterArtConfig.shoulder_depth * r
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
	var ax := BodyLimbs.flat(x3)
	var ay := BodyLimbs.flat(y3)
	var size: Vector2 = face["size"]
	var angle := ay.angle() - PI * 0.5 if ay.length() > 0.05 else ax.angle()  # The art's turn.
	# The art is asked for at whole pixels, as the limbs' is (`BodyLimbs._draw_segment`): the
	# spine's length changes a little every frame as the ragdoll flexes, and a size that is never
	# the same twice paints (and caches) a new texture every frame.
	var art_size := Vector2(roundf(size.x), roundf(size.y))
	var tex: Texture2D
	if face["kind"] == "top":
		tex = PixelArt.render_turned(
			BodyPainter,
			art_size,
			dress.shirt,
			PixelArt.snap_angle(angle),
			dress.shoulder_opts,
		)
	else:
		tex = PixelArt.render_turned(
			TorsoPainter,
			art_size,
			dress.shirt,
			PixelArt.snap_angle(angle),
			dress.torso_opts[face["kind"]],
		)
	return {
		"texture": tex,
		"center": BodyLimbs.flat(face["centre"]),
		"x": ax,
		"y": ay,
		"size": size,
	}


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
		self, wounds, CharacterArtConfig.flesh_crack_color, CharacterArtConfig.flesh_hole_color,
		CharacterArtConfig.flesh_scorch_color,
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
	wound["pos"] = BodyLimbs.flat(skin)
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
	var flat := BodyLimbs.flat(along)
	var angle := flat.angle() - PI * 0.5 if flat.length() > 0.5 else 0.0
	var diameter: float = _hands.hand_radius * 2.0 + 2.0
	var size := Vector2(diameter, diameter)
	var part: Dictionary = dress.hand_parts[hand["side"]]
	var tex := PixelArt.render_turned(
		HandPainter,
		size,
		part["color"],
		PixelArt.snap_angle(angle),
		part["opts"],
	)
	art.append(tex)
	draw_set_transform(BodyLimbs.flat(at), angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The fallen head, its art's front turned the way the face looks; a face turned up or down shows
## its front toward the neck, the crown away from the body.
func _draw_fallen_head(head: Dictionary) -> void:
	var px := ArtCanvasConfig.pixel_size
	var side := (float(HeadPainter.canvas_for(HeadPainter.radius_for(roundi(_character.radius * 2.0
			/ px)))) * px)
	var size := Vector2(side, side)
	var face: Vector3 = head["face"]
	var neck: Vector3 = head["neck"]
	var look := BodyLimbs.flat(face) + BodyLimbs.flat(neck).normalized() * absf(face.z)
	var angle := look.angle() - PI * 0.5 if look.length() > 0.01 else 0.0
	var tex := PixelArt.render_turned(
		HeadPainter,
		size,
		dress.skin,
		PixelArt.snap_angle(angle),
		dress.head_opts,
	)
	art.append(tex)
	draw_set_transform(BodyLimbs.flat(head["at"]), angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
