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

## The textured parts drawn on the body, as meshes kept from draw to draw.
var meshes: BodyMeshes
## The fallen body has been drawn at rest: nothing left to redraw.
var _settled_drawn := false
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
## The crouched or fallen body, laid out from its joints (`body_laid_out.gd`).
var laid: BodyLaidOut

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
	laid = BodyLaidOut.new(self, _character, _hands, dress, limbs)


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
		laid.draw(_character.ragdoll)
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
	var item: Item = _character.inventory.current_item()

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
	key.append(_character.inventory.current_slot())
	# A raised gun is drawn shorter.
	key.append(roundi(_character.weapon.raise() / REDRAW_RAISE_STEP))
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
	var item: Item = _character.inventory.current_item()
	# The weapon goes under the trunk: its butt is tucked behind the shoulder, the barrel shows
	# beyond.
	var weapon := func() -> void:
		if item:
			item.draw_weapon(self, _character)
			draw_order.append(&"weapon")
	laid.draw(rig, false, weapon)
	for hand in 2:
		if pose.arms.grip_height(hand) < HAND_ON_FACE_HEIGHT:
			_draw_hand(hand, pose.hand_angles[hand] - PI * 0.5, [], 0.0)
	draw_order.append(&"hands")
	laid.draw_head(laid.head_part(rig))  # The highest part: over the gun and the fists.
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
