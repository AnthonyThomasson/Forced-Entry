class_name BodyLaidOut extends RefCounted
## The body laid out from its joints (`character_visuals.gd`'s `laid`): once dead the body is the
## ragdoll's, and a living body bent over in a crouch is drawn the same from its rig. Each part is
## drawn from its 3D points seen from above, the lowest first, so a standing body hides its legs
## under the shoulders and a toppling one reveals them, with the trunk a loft of cross-sections
## (`trunk`), so every part foreshortens and rounds off naturally as it tips toward or away from
## the camera. The draw order of parts at about the same height carries over from frame to frame.
## The shadow casts the same parts (`parts_of`). Built once by the visuals.

const HandPainter = preload("res://scenes/character/body/art/hand_painter.gd")
const HeadPainter = preload("res://scenes/character/body/art/head_painter.gd")
const Rig = preload("res://scenes/character/body/character_rig.gd")
## Parts whose heights differ by less than this (px) keep the order they were drawn in last frame.
const STACK_BAND := 3.0

## The trunk (`body_trunk.gd`).
var trunk: BodyTrunk
## The parts' keys, lowest first, as last drawn (see `_stack`).
var _order: Array[String] = []
## The visuals the body is drawn by: their canvas, the art they painted and their draw order.
var _visuals: Node2D
## The character: its radius.
var _character: Node
## The hands: their radius.
var _hands: Node2D
## What the parts are drawn in.
var _dress: BodyDress
## The limbs, whose chains are laid out with the rest.
var _limbs: BodyLimbs


## The laid-out body of `visuals` (`character` and its `hands`), drawn in `dress`, its limbs
## `limbs`.
func _init(
	visuals: Node2D,
	character: Node,
	hands: Node2D,
	dress: BodyDress,
	limbs: BodyLimbs,
) -> void:
	_visuals = visuals
	_character = character
	_hands = hands
	_dress = dress
	_limbs = limbs
	trunk = BodyTrunk.new(visuals, character, dress)


## Every part of the fallen body, lowest first. A living body bent over draws its own head
## (`with_head` off) over the weapon and the hands; `before_trunk` draws the weapon just under the
## trunk.
func draw(rd: RefCounted, with_head := true, before_trunk := Callable()) -> void:
	for part in _stack(parts_of(rd)):
		match part["kind"]:
			"chain":
				_limbs.draw_chain(part)
			"hand":
				_draw_hand(part)
			"head":
				if with_head:
					draw_head(part)
			"trunk":
				if before_trunk.is_valid():
					before_trunk.call()
				trunk.draw(rd)
				if before_trunk.is_valid():
					_visuals.draw_order.append(&"torso")


## `parts` lowest first. The order carries over from the last frame and a pair swaps only once their
## heights differ by more than `STACK_BAND`, so a limb lying across the trunk (their heights
## jittering around each other) stays on one side instead of flickering between over and under.
func _stack(parts: Array) -> Array:
	var rank := {}
	for i in _order.size():
		rank[_order[i]] = i
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
	_order.clear()
	for part in parts:
		_order.append(part["key"])
	return parts


## The fallen body's parts as dicts with their `kind` and mean `height`: limb chains (arms, legs
## with their shoes, the neck), fists, the head and the trunk.
func parts_of(rd: RefCounted) -> Array:
	var r: float = _character.radius
	var parts := []
	var chains := _limbs.chains(rd)
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
		_limbs.segment(chest, head, neck, neck, neck_length),
		_dress.skin,
	)
	parts.append(_keyed(_limbs.chain_of([neck_seg]), "neck"))
	parts.append(head_part(rd))
	parts.append({
		"kind": "trunk",
		"key": "trunk",
		"height": (chest.z + rd.point(Rig.PELVIS).z) * 0.5,
	})
	return parts


## The head as a fallen-body part: where it is, the way it faces and the neck it sits on.
func head_part(rd: RefCounted) -> Dictionary:
	var head: Vector3 = rd.point(Rig.HEAD)
	return { "kind": "head", "key": "head", "at": head, "height": head.z, "face": rd.face(),
		"neck": rd.point(Rig.CHEST) - head }


## `part` tagged with the stable `key` its draw order is remembered by.
func _keyed(part: Dictionary, key: String) -> Dictionary:
	part["key"] = key
	return part


## A fallen fist, its knuckles along the forearm.
func _draw_hand(hand: Dictionary) -> void:
	var at: Vector3 = hand["at"]
	var along: Vector3 = hand["along"]
	var flat := BodyLimbs.flat(along)
	var angle := flat.angle() - PI * 0.5 if flat.length() > 0.5 else 0.0
	var diameter: float = _hands.hand_radius * 2.0 + 2.0
	var size := Vector2(diameter, diameter)
	var part: Dictionary = _dress.hand_parts[hand["side"]]
	var tex := PixelArt.render_turned(
		HandPainter,
		size,
		part["color"],
		PixelArt.snap_angle(angle),
		part["opts"],
	)
	_visuals.art.append(tex)
	_visuals.draw_set_transform(BodyLimbs.flat(at), angle, Vector2.ONE)
	_visuals.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	_visuals.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The fallen head, its art's front turned the way the face looks; a face turned up or down shows
## its front toward the neck, the crown away from the body.
func draw_head(head: Dictionary) -> void:
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
		_dress.skin,
		PixelArt.snap_angle(angle),
		_dress.head_opts,
	)
	_visuals.art.append(tex)
	_visuals.draw_set_transform(BodyLimbs.flat(head["at"]), angle, Vector2.ONE)
	_visuals.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	_visuals.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
