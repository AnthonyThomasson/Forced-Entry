class_name BodyShadow extends RefCounted
## The body's floor shadow (`character_visuals.gd`'s `shadow`): a CanvasGroup behind the body
## carrying the shadow's alpha, around the node the shadow draws on (opaque, so overlapping parts
## merge into one shade). Standing, the limbs, fists and head after the shoulders' silhouette (which
## the visuals draw, from their shoulder art); fallen or folded, every part of the laid-out body.
## Each point is shifted away from the light by its height (`cast`). Built once by the visuals,
## which connect the node's draw. Tuning: CharacterShadowConfig.body_shadow_per_height and
## ArtCanvasConfig's light_from and drop_shadow_alpha.

const BodyMeshes = preload("res://scenes/character/body/body_meshes.gd")
const Rig = preload("res://scenes/character/body/character_rig.gd")

## The node the shadow draws on, inside the shadow group.
var node: Node2D
## The textured and plain parts drawn on the shadow, as meshes kept from draw to draw.
var meshes: BodyMeshes
## The visuals the shadow lies under (its transform, the limb chains, the laid-out parts).
var _visuals: Node2D
## The character: its radius.
var _character: Node
## The hands: their radius.
var _hands: Node2D


## The shadow of `visuals`' body (`character` and its `hands`), its group added under `visuals`.
func _init(visuals: Node2D, character: Node, hands: Node2D) -> void:
	_visuals = visuals
	_character = character
	_hands = hands
	var group := CanvasGroup.new()
	group.show_behind_parent = true
	group.self_modulate = Color(1.0, 1.0, 1.0, ArtCanvasConfig.drop_shadow_alpha)
	visuals.add_child(group)
	node = Node2D.new()
	meshes = BodyMeshes.new(node)
	group.add_child(node)


## How far a point on the body is shifted on the floor shadow per px of its height: away from the
## light (see `cast`).
func shift() -> Vector2:
	return _visuals.global_transform.basis_xform_inv(
		-ArtCanvasConfig.light_from.normalized(),
	).normalized() * CharacterShadowConfig.body_shadow_per_height


## A 3D point's place on the floor shadow: its flat position shifted away from the light by its
## height (`shift`, from `shift()`, per px).
static func cast(p: Vector3, shift_by: Vector2) -> Vector2:
	return Vector2(p.x, p.y) + shift_by * p.z


## The standing body's floor shadow from `rig` after the shoulders' silhouette (drawn at `lift`):
## each limb, fist and the head, every point shifted from the light by `shift_by` per px of height.
func draw_standing(rig: Rig, shift_by: Vector2, lift: Vector2) -> void:
	var limbs: Array = _visuals.limbs.chains(rig)
	# All one black (the shadow group shows what any part covers, whatever the order): one kept
	# mesh, or without meshes one batch.
	var solid: BodyMeshes.Solid = null
	var fills: RefCounted = null
	if BodyMeshes.enabled:
		solid = meshes.solid(Color.BLACK)
		fills = solid
	else:
		fills = FillBatch.new(node)
	var bounds := Rect2(lift, Vector2.ZERO)  # What the limbs and the discs cover.
	for i in 2:
		for chain in [limbs[i], limbs[2 + i]]:
			bounds = bounds.merge(_draw_limb(chain, shift_by, fills))
		var hand := cast(rig.point(Rig.HAND[i]), shift_by)
		fills.circle(hand, _hands.hand_radius, Color.BLACK)
		bounds = bounds.merge(Rect2(hand, Vector2.ZERO).grow(_hands.hand_radius))
	var head := cast(rig.point(Rig.HEAD), shift_by)
	var head_radius: float = CharacterRagdollConfig.head_radius * _character.radius
	fills.circle(head, head_radius, Color.BLACK)
	if solid:
		solid.flush(bounds.merge(Rect2(head, Vector2.ZERO).grow(head_radius)))
	else:
		fills.flush()


## The fallen (or folded) body's floor shadow from the joints of `rd`: each part's silhouette with
## every point shifted away from the light by its height, so the shadow closes in under the body as
## it lands.
func draw_fallen(rd: RefCounted) -> void:
	var shift_by := shift()
	var fills := FillBatch.new(node)
	for part in _visuals._fallen_parts(rd):
		match part["kind"]:
			"chain":
				_draw_limb(part, shift_by, fills)
			"hand":
				fills.circle(cast(part["at"], shift_by), _hands.hand_radius, Color.BLACK)
			"head":
				fills.circle(
					cast(part["at"], shift_by),
					CharacterRagdollConfig.head_radius * _character.radius,
					Color.BLACK,
				)
	# The trunk's slices, each its own polygon: the shadow group flattens overlapping black into one
	# shade, so they render as the one outline the body draws, without the union that outline costs.
	for hull in _visuals.trunk.hulls(rd, shift_by):
		fills.fill(hull, Color.BLACK)
	fills.flush()  # All one black: the shadow group shows what any part covers, whatever the order.


## One limb chain's floor shadow: each segment's capsule shifted from the light (`cast`), added to
## `fills` (a `FillBatch` or a `BodyMeshes.Solid`). Returns the rect the capsules lie in.
func _draw_limb(chain: Dictionary, shift_by: Vector2, fills: RefCounted) -> Rect2:
	var bounds := Rect2()
	var reach := 0.0
	for seg in chain["segs"]:
		var a := cast(seg["a"], shift_by)
		var b := cast(seg["b"], shift_by)
		var ra: float = seg["ra"]
		var rb: float = seg["rb"]
		BodyLimbs.fill_capsule(
			fills, BodyLimbs.capsule(a, b, ra, rb), BodyLimbs.convex(a, b, ra, rb), Color.BLACK,
		)
		bounds = Rect2(a, Vector2.ZERO) if reach == 0.0 else bounds.expand(a)
		bounds = bounds.expand(b)
		reach = maxf(reach, maxf(seg["ra"], seg["rb"]))
	return bounds.grow(reach)
