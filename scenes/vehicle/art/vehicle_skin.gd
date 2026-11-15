class_name VehicleSkin
extends RefCounted
## Vehicles domain, the 2D art on the 3D vehicle (#193 phase 2b, `domain-art/textured-toon.md`): the
## textures `vehicle_mesh.gd` projects straight down onto a hull and a door leaf, so a car seen
## from above reads as the 2D car does. Each is made once per kind, paint (and door) from the
## painters' flat paint (`PixelArt.render_flat`, `domain-art/flat-paint.md`: albedo, no light, in
## the painters' canonical frame, front toward +y) and held here, so a texture is never made per
## frame and the textured material (one per texture) stays one per kind and paint.
##
## The painters draw in Art's canonical frame and the 2D draws them turned onto the vehicle's by
## `BODY_TURN`; the mesh is in the vehicle's frame (x forward, y right, model `x, z`), and a
## texture is sampled along model `x` (u) and `z` (v), so each image is turned here to that frame
## and `rect` (px, the vehicle's frame) is where it lies: the mesh turns, the art is made once.

const CarPainter = preload("res://scenes/vehicle/art/car_painter.gd")
const VanPainter = preload("res://scenes/vehicle/art/van_painter.gd")
const DoorPainter = preload("res://scenes/vehicle/art/door_painter.gd")
const Art = preload("res://scenes/vehicle/art/vehicle_art.gd")
## The body painter of each kind (the 2D layers' own).
const PAINTERS := { &"car": CarPainter, &"van": VanPainter }
const METAL := "metal"
const GLASS := "glass"

## `kind|paint` -> the body's `{ texture, rect }`; `kind|paint|door` -> a door's.
static var _skins: Dictionary = {}


## How many skins are held (a test reads it).
static func count() -> int:
	return _skins.size()


## Forget every skin (a test, or a repaint of the painters).
static func clear() -> void:
	_skins.clear()


## The body of a `kind` painted `paint`: its chassis with its roof over it, turned onto the
## vehicle's frame, with the `rect` it covers (the body's own footprint, centred on the origin).
## The side windows are not on it (they are each door's `glass`, which goes with the door), so an
## open door shows the cabin. The paint fills what the art leaves clear (a rounded corner the
## hull's outline overshoots), so no texel is see-through. `{ texture: Texture2D, rect: Rect2 }`.
static func body(kind: StringName, paint: Color) -> Dictionary:
	var key := "%s|%s" % [kind, paint.to_html()]
	if _skins.has(key):
		return _skins[key]
	var under := _composite(kind, paint)
	# BODY_TURN is a quarter turn back (counter-clockwise on the screen)
	under.rotate_90(COUNTERCLOCKWISE)
	var size: Vector2 = VehicleConfig.kinds[kind]["size"]
	var skin := {
		"texture": ImageTexture.create_from_image(under),
		"rect": Rect2(-size * 0.5, size),
	}
	_skins[key] = skin
	return skin


## The glass of door `def` of a `kind` painted `paint`: the body's art under the door's side window
## (a pane of the 2D `glass` part blended over it, so the texture is whole: the window and what
## lies round it), turned onto the vehicle's frame, with the `rect` (px, the vehicle's frame) it
## covers. A pane the mesh lays over the hull and fades as the door opens, as the 2D window does.
## `{ texture: Texture2D, rect: Rect2 }`, empty for a door with no window.
static func glass(kind: StringName, def: Dictionary, paint: Color) -> Dictionary:
	if not (VehicleConfig.looks[kind]["glass"] as Dictionary).has(def["id"]):
		return {}
	var key := "%s|%s|%s|glass" % [kind, paint.to_html(), def["id"]]
	if _skins.has(key):
		return _skins[key]
	var image := _composite(kind, paint)
	var canonical := Vector2(image.get_size())
	var at := _blend_window(image, kind, def, paint)
	var crop := image.get_region(at)
	crop.rotate_90(COUNTERCLOCKWISE)
	# the crop's canonical pixels, as vehicle px: x = v - h / 2, y = w / 2 - u (less its width)
	var covers := Rect2(
		Vector2(at.position.y - canonical.y * 0.5, canonical.x * 0.5 - at.end.x),
		Vector2(at.size.y, at.size.x),
	)
	var skin := { "texture": ImageTexture.create_from_image(crop), "rect": covers }
	_skins[key] = skin
	return skin


## Door `def`'s side-window pane blended over `image` (the canonical body) where the 2D draws it;
## the canonical pixels it covers.
static func _blend_window(image: Image, kind: StringName, def: Dictionary, paint: Color) -> Rect2i:
	var rect: Rect2 = DoorPainter.glass_rect(kind, def["id"])
	var size := Vector2(rect.size.y, rect.size.x)
	var opts := { "kind": kind, "door": def["id"], "part": "glass", "material": GLASS }
	var pane := _image(PixelArt.render_flat(DoorPainter, size, paint, opts))
	# vehicle (x, y) is canonical (w/2 - y, h/2 + x), the body's own mapping (`Art.at`)
	var centre := rect.get_center()
	var middle := Vector2(image.get_width() * 0.5 - centre.y, image.get_height() * 0.5 + centre.x)
	var corner := Vector2i((middle - size * 0.5).round())
	image.blend_rect(pane, Rect2i(Vector2i.ZERO, pane.get_size()), corner)
	return Rect2i(corner, pane.get_size())


## The wing mirror of a `kind` painted `paint`, turned onto the leaf's frame (the mirror's
## `mirror_size` out x along, as the mesh's box lies). One per paint. `{ texture: Texture2D }`.
static func mirror(kind: StringName, paint: Color) -> Dictionary:
	var key := "%s|%s|mirror" % [kind, paint.to_html()]
	if _skins.has(key):
		return _skins[key]
	var size := Vector2(VehicleMeshConfig.mirror_size.x, VehicleMeshConfig.mirror_size.y)
	# (the painter wants a door of the kind, though a mirror looks the same on each)
	var on: StringName = (VehicleConfig.looks[kind]["mirror"] as Array)[0]
	var opts := { "kind": kind, "door": on, "part": "mirror", "material": METAL }
	var image := _image(PixelArt.render_flat(DoorPainter, size, paint, opts))
	image.rotate_90(COUNTERCLOCKWISE)
	var skin := { "texture": ImageTexture.create_from_image(image) }
	_skins[key] = skin
	return skin


## The body's chassis with its roof over it on the paint, in the painters' canonical frame.
static func _composite(kind: StringName, paint: Color) -> Image:
	var size: Vector2 = VehicleConfig.kinds[kind]["size"]
	var canonical := Vector2(size.y, size.x)
	var painter: Script = PAINTERS[kind]
	var image := _image(PixelArt.render_flat(painter, canonical, paint, _opts(kind, "chassis")))
	var under := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	under.fill(paint)
	under.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	var roof := _image(PixelArt.render_flat(painter, canonical, paint, _opts(kind, "roof")))
	under.blend_rect(roof, Rect2i(Vector2i.ZERO, roof.get_size()), Vector2i.ZERO)
	return under


## Door `def` of a `kind` painted `paint`: its panel (the door seen from above, shut), turned onto
## the frame of its hinge (the leaf's own, origin at the hinge) with the `rect` it covers there.
## `{ texture: Texture2D, rect: Rect2 }`.
static func door(kind: StringName, def: Dictionary, paint: Color) -> Dictionary:
	var key := "%s|%s|%s" % [kind, paint.to_html(), def["id"]]
	if _skins.has(key):
		return _skins[key]
	var frame := Art.door_frame(def)
	var depth: float = VehicleConfig.looks[kind]["door_depth"]
	var size := Vector2(depth, frame["length"])
	var opts := { "kind": kind, "door": def["id"], "part": "panel", "material": METAL }
	var image := _image(PixelArt.render_flat(DoorPainter, size, paint, opts))
	# as the 2D draws it: the image's rect about the hinge, turned by the door's own `turn`
	var at := Rect2(Vector2(-depth if frame["outer"] > 0.0 else 0.0, -size.y), size)
	var turned := Transform2D(frame["turn"], Vector2.ZERO) * at
	for i in posmod(roundi(float(frame["turn"]) / (PI * 0.5)), 4):
		image.rotate_90(CLOCKWISE)
	var snap := Vector2(0.001, 0.001)
	var skin := {
		"texture": ImageTexture.create_from_image(image),
		"rect": Rect2(turned.position.snapped(snap), turned.size.snapped(snap)),
	}
	_skins[key] = skin
	return skin


## A flat texture's pixels as RGBA8 (a copy the caller may draw into and turn).
static func _image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


## The painter options of a body's `part`.
static func _opts(kind: StringName, part: String) -> Dictionary:
	return { "kind": kind, "part": part, "material": METAL }
