class_name BodyTextures
extends RefCounted
## Character body, the 2D art on the 3D body (`body_mesh.gd`): the flat render of
## each painter (`PixelArt.render_flat`: the art with no light of its own, the toon bands light it)
## mapped onto the part the 2D draws it for (`MeshPart`, read as the textured toon reads it). The
## art is angle-free, so it is one texture per part per look (`PixelArt` caches it), set when the
## look changes and never per frame; the parts turn and stretch with the pose and the art stays put
## on them (the textured toon projects in the part's own model space).
##
## What goes where:
## - the shoulders (`BodyPainter`: the shirt's collar, sleeve ends, vest top, plates, the pack's
##   straps, the neck's ring) on the trunk and the vest, 1 art px to 1 world px, centred on the
##   trunk's axis; the pack's rectangle of it on the pack's box;
## - the head (`HeadPainter`: skin, hair or a cap or helmet, implants) on the head's dome and on the
##   hair's and headwear's domes over it: the art's disc is the dome's equator, its front the
##   face's front; and the whole canvas (a brim, ear pods, goggles and the hair's fall lie past the
##   disc) on a cut-out sprite laid flat over the crown, so seen from above the head is the 2D one;
## - a fist (`HandPainter`) on its ball, which turns with the hand's angle;
## - a limb's strip (`LimbPainter`: a sleeve, a trouser leg, a boot's shaft; across it, along it)
##   on the limb's top, the limb solid lying along its z axis (`BodySolids`): the strip's width
##   across, its length from the joint nearer the body; the shin is the knee's and the shin's
##   strips as one; the shoe is its strip over its footprint.
## The neck, the face's band and the plates stay plain colour. A part's art is not clear everywhere
## (a disc's rim, a pack's rounded corners, the ends of a strip): there it shows the part's vertex
## colour, which is the colour of the part (`BodyMesh._coat`), never white.

const BodyPainter = preload("res://scenes/character/body/art/body_painter.gd")
const HeadPainter = preload("res://scenes/character/body/art/head_painter.gd")
const HandPainter = preload("res://scenes/character/body/art/hand_painter.gd")
const LimbPainter = preload("res://scenes/character/body/art/limb_painter.gd")
## Where a boot's shaft starts along the shin (0 knee, 1 ankle) and how much wider than a shoe's
## strip it is (body radii), so the shaft reads over the shoe.
const BOOT_TOP := 0.62
const BOOT_GROW := 0.06
## How far inside the art's rim a dome's equator lies (art px): the dome ends on art, not on the
## clear texel past it.
const DOME_INSET := 0.25

## The shin's two strips are one texture: `[knee, shin, composite]` by the knee's and the shin's
## instance ids (the pair is held, so a freed texture's id is never reused for another).
static var _shins := {}


## Put the look `dress` resolved on the `parts` of a body of radius `r` whose fists are
## `hand_radius` px (`BodyMesh`'s indices).
static func apply(
	parts: Array[MeshPart],
	dress: BodyDress,
	r: float,
	hand_radius: float,
) -> void:
	_trunk(parts, dress, r)
	_head(parts, dress, r)
	_hands(parts, dress, hand_radius)
	var arm: Array = CharacterArtConfig.body_arm_widths
	var leg: Array = CharacterArtConfig.body_leg_widths
	for i in 2:
		var upper: Dictionary = dress.arm_parts[i]["upper"]
		var fore: Dictionary = dress.arm_parts[i]["fore"]
		_limb(
			parts[BodyMesh.UPPER + i],
			_strip(upper, arm[0], arm[1], CharacterBodyConfig.upper_arm, r),
			r,
		)
		_limb(
			parts[BodyMesh.FORE + i],
			_strip(fore, arm[1], arm[2], CharacterBodyConfig.forearm, r),
			r,
		)
		var opts: Dictionary = dress.leg_opts[i]
		_limb(
			parts[BodyMesh.THIGH + i],
			_strip(_part(dress.pants, opts["thigh"]), leg[0], leg[1], CharacterBodyConfig.thigh, r),
			r,
		)
		_shin(parts[BodyMesh.SHIN + i], dress, i, r)
		if dress.boots:
			_boot(parts[BodyMesh.BOOT + i], dress, i, r)
		_foot(parts[BodyMesh.FOOT + i], dress, i, r)


## The shoulders' art on the trunk and the vest (the same texture over the trunk's and the vest's
## own scale), and the pack's rectangle of it on the pack's box.
static func _trunk(parts: Array[MeshPart], dress: BodyDress, r: float) -> void:
	var size := Vector2(r * 2.0, r * 2.0)
	var tex := PixelArt.render_flat(BodyPainter, size, dress.shirt, dress.shoulder_opts)
	var half := BodyMesh.trunk_half(r)
	_put(parts[BodyMesh.TORSO], tex, _centred(size, half))
	_put(parts[BodyMesh.VEST], tex, _centred(size, half * CharacterMeshConfig.vest_grow))
	# The pack's rectangle in the art, centred on the shoulders' own centre, over the box's top.
	var pack := Rect2(BodyPainter.pack_rect(int(size.x), int(size.y)))
	_put(
		parts[BodyMesh.PACK],
		tex,
		Rect2((-size * 0.5 - pack.get_center()) / pack.size, size / pack.size),
	)


## The head's art on the head's dome, and on the hair's and the headwear's over it (one rect: the
## art's disc is each dome's equator), and the whole canvas on the sprite over the crown.
static func _head(parts: Array[MeshPart], dress: BodyDress, r: float) -> void:
	var px := ArtCanvasConfig.pixel_size
	var disc := HeadPainter.radius_for(roundi(r * 2.0 / px))
	var side := head_side(r)
	var size := Vector2(side, side)
	var tex := PixelArt.render_flat(HeadPainter, size, dress.skin, dress.head_opts)
	var rect := _disc_rect(size, Vector2.ONE * (disc + DOME_INSET) * px)
	for index in [BodyMesh.HEAD, BodyMesh.HAIR, BodyMesh.HEADWEAR]:
		_put(parts[index], tex, rect)
	_put(parts[BodyMesh.CROWN], tex, _disc_rect(size, size), true)


## The side of the head's art canvas (px) for a body of radius `r`, which is the side of the sprite
## over the crown.
static func head_side(r: float) -> float:
	var px := ArtCanvasConfig.pixel_size
	return float(HeadPainter.canvas_for(HeadPainter.radius_for(roundi(r * 2.0 / px)))) * px


## Each fist's art on its ball: the art's disc is the ball's equator.
static func _hands(parts: Array[MeshPart], dress: BodyDress, hand_radius: float) -> void:
	var diameter := hand_radius * 2.0 + 2.0
	var size := Vector2(diameter, diameter)
	var disc := HandPainter.fist_radius(int(diameter), int(diameter))
	for i in 2:
		var part: Dictionary = dress.hand_parts[i]
		var tex := PixelArt.render_flat(HandPainter, size, part["color"], part["opts"])
		_put(parts[BodyMesh.HAND + i], tex, _disc_rect(size, Vector2.ONE * (disc + DOME_INSET)))


## Side `i`'s shin: the knee's strip over the shin's, as one texture along the shin's solid.
static func _shin(node: MeshPart, dress: BodyDress, i: int, r: float) -> void:
	var leg: Array = CharacterArtConfig.body_leg_widths
	var opts: Dictionary = dress.leg_opts[i]
	var shin := CharacterBodyConfig.shin * r
	var knee := _strip(_part(dress.pants, opts["knee"]), leg[1], leg[2], shin * 0.35 / r, r)
	var calf := _strip(
		_part(dress.shin_colour(i), opts["shin"]),
		leg[2],
		leg[3],
		shin * 0.65 / r,
		r,
	)
	var tex := _stacked(knee, calf)
	var across := tex.get_width() / BodyMesh.limb_thick(r)
	_put(node, tex, Rect2(-across * 0.5, 0.0, across, 1.0))


## Side `i`'s boot's shaft on its straight solid (the shaft's strip, in the shoes' colour).
static func _boot(node: MeshPart, dress: BodyDress, i: int, r: float) -> void:
	var leg: Array = CharacterArtConfig.body_leg_widths
	var opts: Dictionary = dress.leg_opts[i]
	var top := lerpf(leg[2], leg[3], (BOOT_TOP - 0.35) / 0.65) + BOOT_GROW
	var strip := _strip(
		_part(dress.shoes, opts["shaft"]),
		top,
		leg[3] + BOOT_GROW,
		CharacterBodyConfig.shin * (1.0 - BOOT_TOP),
		r,
	)
	_limb(node, strip, r, BodyMesh.boot_radius(r))


## Side `i`'s shoe (a boot's a little wider): its strip over the footprint of its solid, the toe
## along its +z.
static func _foot(node: MeshPart, dress: BodyDress, i: int, r: float) -> void:
	var shoe: Array = CharacterArtConfig.body_shoe_widths
	var grow := BOOT_GROW if dress.boots else 0.0
	var strip := _strip(
		_part(dress.shoes, dress.leg_opts[i]["foot"]),
		shoe[0] + grow,
		shoe[1] + grow,
		CharacterBodyConfig.foot,
		r,
	)
	_put(node, strip["tex"], Rect2(-0.5, -0.5, 1.0, 1.0))


## A limb segment's art: its flat strip as the limb painter paints it (the canvas as wide as the
## widest end across, as long as the segment and its two end caps), by the segment's `part`
## (`color`, `opts`) between the widths `wa` and `wb` (body radii) and `length` (body radii) long.
## Returns the texture, the canvas's size and the first end cap's size along it.
static func _strip(part: Dictionary, wa: float, wb: float, length: float, r: float) -> Dictionary:
	var ra := wa * r * 0.5
	var rb := wb * r * 0.5
	var size := Vector2(roundf(maxf(ra, rb) * 2.0), roundf(length * r + ra + rb))
	return {
		"tex": PixelArt.render_flat(LimbPainter, size, part["color"], part["opts"]),
		"size": size,
		"cap": ra,
		"length": length * r,
	}


## A segment's `color` and painter `opts` as a part (`BodyDress` holds arm parts so).
static func _part(color: Color, opts: Dictionary) -> Dictionary:
	return { "color": color, "opts": opts }


## `strip` (`_strip`) on a limb's node whose solid is `across` px per unit wide (the limb's own
## thickness by default): across the strip is across the limb, its length is the limb's.
static func _limb(node: MeshPart, strip: Dictionary, r: float, across := 0.0) -> void:
	var per := across if across > 0.0 else BodyMesh.limb_thick(r)
	var size: Vector2 = strip["size"]
	var length: float = strip["length"]
	_put(
		node,
		strip["tex"],
		Rect2(-size.x * 0.5 / per, -float(strip["cap"]) / length, size.x / per, size.y / length),
	)


## The knee's strip over the shin's as one texture: each one's own rows (past its first end cap, a
## segment long), centred over the wider one. Made once for a pair of textures.
static func _stacked(upper: Dictionary, lower: Dictionary) -> Texture2D:
	var a: Texture2D = upper["tex"]
	var b: Texture2D = lower["tex"]
	var key := "%d|%d" % [a.get_instance_id(), b.get_instance_id()]
	if _shins.has(key):
		return _shins[key][2]
	var width := maxi(a.get_width(), b.get_width())
	var rows: Array[Rect2i] = [_core(upper, a), _core(lower, b)]
	var image := Image.create(width, rows[0].size.y + rows[1].size.y, false, Image.FORMAT_RGBA8)
	var at := 0
	for k in 2:
		var source: Image = (a if k == 0 else b).get_image()
		image.blit_rect(source, rows[k], Vector2i(int((width - source.get_width()) / 2.0), at))
		at += rows[k].size.y
	var tex := ImageTexture.create_from_image(image)
	_shins[key] = [a, b, tex]  # holding both keeps their ids from being reused
	return tex


## The rows of `strip`'s image (`tex`) that are its segment's own: past the end cap behind its first
## joint, the segment's length.
static func _core(strip: Dictionary, tex: Texture2D) -> Rect2i:
	var from := mini(roundi(strip["cap"]), tex.get_height() - 1)
	var rows := clampi(roundi(strip["length"]), 1, tex.get_height() - from)
	return Rect2i(0, from, tex.get_width(), rows)


## `tex` over a part in `rect` (model units), tinted white so the art shows as painted; `cutout`
## draws nothing where it is clear.
static func _put(node: MeshPart, tex: Texture2D, rect: Rect2, cutout := false) -> void:
	node.texture = tex
	node.rect = rect
	node.cutout = cutout
	node.tint = Color.WHITE


## The rect of an art canvas `size` px, centred on the part's axis, for a part whose model unit is
## `per_unit` px across and deep (x, then z).
static func _centred(size: Vector2, per_unit: Vector2) -> Rect2:
	return Rect2(-size * 0.5 / per_unit, size / per_unit)


## The rect of a disc painter's canvas `size` px over a part whose model unit is `per_unit` px
## across and deep (x, then z), the disc's centre on the part's axis. The painters centre the disc
## on the pixel `int(w / 2)`, whose centre is half an art pixel past the canvas's own: centring the
## canvas would leave a dome's rim on clear texels on one side.
static func _disc_rect(size: Vector2, per_unit: Vector2) -> Rect2:
	var px := ArtCanvasConfig.pixel_size
	var at := Vector2(int(size.x / px / 2.0) + 0.5, int(size.y / px / 2.0) + 0.5) * px
	return Rect2(-at / per_unit, size / per_unit)
