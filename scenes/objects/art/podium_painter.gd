extends RefCounted
## Pixel-art PODIUM painter (Objects domain, private): a segment of the concrete band along the
## outside of a tower's exterior wall, seen from above: a thick slab with joints cut across it and
## pillars standing along its street edge. Canonical frame: the street (the band's outer edge)
## toward +y, the length across x. Knobs: ObjectArtPodiumConfig.podium_*, each overridable by `opts`
## (keyed without the prefix); the painter takes its colour as given (`ObjectArt.AS_GIVEN`). Run
## down (decay.gd): grime and rust.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")
## The slab's height for cast shadows.
const _SLAB_HEIGHT := 8


## Paint the band segment onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var slab: Color = opts.get("color", ObjectArtPodiumConfig.podium_color)
	var all := Rect2i(0, 0, c.w, c.h)
	var shape := PixelShape.rounded(all, 0)
	c.fill(shape, slab, 2)
	c.surface(shape, "stone", slab)
	var joints: int = opts.get("joint_step", ObjectArtPodiumConfig.podium_joint_step)
	for x in range(joints, c.w, joints):
		Kit.fill_rect(c, Rect2i(x, 0, 1, c.h), slab.darkened(0.3))
	_pillars(c, slab, opts)
	c.bevel(shape, 1, 2, slab.lightened(0.25), slab.darkened(0.4))
	c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, 2)


## The pillars along the street edge, one every `pillar_step`, each `pillar_px` square.
static func _pillars(c: PixelCanvas, slab: Color, opts: Dictionary) -> void:
	var step: int = opts.get("pillar_step", ObjectArtPodiumConfig.podium_pillar_step)
	var size: int = mini(opts.get("pillar_px", ObjectArtPodiumConfig.podium_pillar_px), c.h - 2)
	for x in range(int(step / 4.0), c.w - size, step):
		var pillar := Rect2i(x, c.h - size - 1, size, size)
		Tech.box(c, pillar, slab.lightened(0.1), _SLAB_HEIGHT + 6, 1)
		Kit.fill_rect(c, pillar.grow(-3), slab.darkened(0.12))
