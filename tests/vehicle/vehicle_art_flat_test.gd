extends GameTest
## The car and van painters' flat read and the skins the 3D vehicle wears (#193 phase 2b,
## Vehicles): the 2D art keeps its exact pixels (pinned by hash), the flat paint (no light) draws
## the roof panel in the paint with no ring round it, and `VehicleSkin` turns the painters'
## canonical art (front toward +y) onto the mesh's frame (x forward) once per kind and paint: the
## head lamps lie at the nose's end, the tail lamps at the tail's, the paint is the vehicle's, a
## door's art lies where its leaf does.

const CarPainter := preload("res://scenes/vehicle/art/car_painter.gd")
const VanPainter := preload("res://scenes/vehicle/art/van_painter.gd")
const DoorPainter := preload("res://scenes/vehicle/art/door_painter.gd")
const Art := preload("res://scenes/vehicle/art/vehicle_art.gd")
const VehicleMesh := preload("res://scenes/vehicle/art/vehicle_mesh.gd")
const BLUE := Color(0.15, 0.25, 0.7)
## Pixel hashes of the lit 2D paints (`render_turned` at 0.7 rad), taken before the flat read.
const GOLDEN := {
	"car_chassis": 914_874_176,
	"car_roof": 2_201_908_112,
	"van_chassis": 1_193_170_021,
	"van_roof": 1_838_978_537,
	"car_door": 2_669_629_823,
	"van_slide": 3_845_355_223,
	"car_mirror": 4_066_469_226,
}


func describe() -> Dictionary:
	return {
		"name": "The vehicle painters read flat, and the skins turn their art onto the mesh",
		"description": "2D pixels of the car, van, door and mirror unchanged; a flat roof panel is "
			+ "the paint with no ring; VehicleSkin's body and door textures lie in the mesh's "
			+ "frame, are cached, and carry the vehicle's paint.",
		"tags": ["vehicle", "art", "3d", "scripted"],
		"timeout": 30.0,
	}


func run(t: TestContext) -> void:
	_two_d_untouched(t)
	_flat_roof_panel(t)
	_body_skin(t, &"car", CarPainter)
	_body_skin(t, &"van", VanPainter)
	_door_skin(t)
	_cached(t)


## The lit 2D paints have the pixels they had before the flat read.
func _two_d_untouched(t: TestContext) -> void:
	var cases := {
		"car_chassis": [CarPainter, &"car", "chassis"],
		"car_roof": [CarPainter, &"car", "roof"],
		"van_chassis": [VanPainter, &"van", "chassis"],
		"van_roof": [VanPainter, &"van", "roof"],
	}
	for id: String in cases:
		var c: Array = cases[id]
		var size := _canonical(c[1])
		var opts := { "kind": c[1], "part": c[2], "material": "metal" }
		var image := PixelArt.render_turned(c[0], size, BLUE, 0.7, opts).get_image()
		_pinned(t, id, image)
	_doors_untouched(t)


## The lit door panels and the wing mirror have their old pixels.
func _doors_untouched(t: TestContext) -> void:
	var car_door: Dictionary = VehicleConfig.kinds[&"car"]["doors"][0]
	var van_slide: Dictionary = _slide_door()
	for pair: Array in [["car_door", &"car", car_door], ["van_slide", &"van", van_slide]]:
		var def: Dictionary = pair[2]
		var size := Vector2(
			VehicleConfig.looks[pair[1]]["door_depth"], Art.door_frame(def)["length"]
		)
		var opts := { "kind": pair[1], "door": def["id"], "part": "panel", "material": "metal" }
		_pinned(t, pair[0], PixelArt.render_turned(DoorPainter, size, BLUE, 0.7, opts).get_image())
	var mirror := PixelArt.render_turned(DoorPainter, Vector2(5, 8), BLUE, 0.7, {
		"kind": &"car", "door": &"front_left", "part": "mirror", "material": "metal",
	})
	_pinned(t, "car_mirror", mirror.get_image())


## A lit paint's hash is its golden one.
func _pinned(t: TestContext, id: String, image: Image) -> void:
	var got := hash(image.get_data())
	t.check(got == GOLDEN[id], "the lit 2D %s paint has its old pixels (%d)" % [id, got])


## The flat paint: the roof panel is the paint (not the lit tone) and has no shadow ring, the lit
## one has its light tone and its ring.
func _flat_roof_panel(t: TestContext) -> void:
	for kind: StringName in [&"car", &"van"]:
		var painter: Script = CarPainter if kind == &"car" else VanPainter
		var size := _canonical(kind)
		var opts := { "kind": kind, "part": "roof", "material": "metal" }
		var flat := PixelArt.render_flat(painter, size, BLUE, opts).get_image()
		var lit := PixelArt.render_turned(painter, size, BLUE, 0.0, opts).get_image()
		var look: Dictionary = VehicleConfig.looks[kind]
		var roof: Vector2 = look["roof"]
		var at := _texel(size, Vector2((roof.x + roof.y) * 0.5 - 6.0, 4.0))
		t.check(
			PixelCanvas._same(flat.get_pixel(at.x, at.y), BLUE),
			"%s: a flat roof panel is the paint (%s)" % [kind, flat.get_pixel(at.x, at.y)],
		)
		t.check(
			not PixelCanvas._same(lit.get_pixel(at.x, at.y), BLUE),
			"%s: the lit roof panel is a lighter tone" % kind,
		)
		var shadow := ArtSurfaceConfig.tones(BLUE)["shadow"] as Color
		t.check(_count(flat, shadow) < _count(lit, shadow), "%s: no shadow ring in flat" % kind)


## The body skin of `kind`: the mesh's frame, the paint, the lamps where the vehicle has them.
func _body_skin(t: TestContext, kind: StringName, _painter: Script) -> void:
	var length_width: Vector2 = VehicleConfig.kinds[kind]["size"]
	var skin := VehicleSkin.body(kind, BLUE)
	var texture: Texture2D = skin["texture"]
	var image := texture.get_image()
	t.expect_eq(Vector2(image.get_size()), length_width, "%s: the skin is length x width" % kind)
	t.check(
		skin["rect"] == Rect2(-length_width * 0.5, length_width),
		"%s: it covers the body" % kind,
	)
	_lamps_and_paint(t, kind, image)
	var opaque := true
	for y in image.get_height():
		for x in image.get_width():
			opaque = opaque and image.get_pixel(x, y).a > 0.99
	t.check(opaque, "%s: no texel is see-through" % kind)


## The head lamp at the skin's nose end, the tail lamp at its tail end, the roof in the paint.
func _lamps_and_paint(t: TestContext, kind: StringName, image: Image) -> void:
	var look: Dictionary = VehicleConfig.looks[kind]
	var length_width: Vector2 = VehicleConfig.kinds[kind]["size"]
	var half := length_width * 0.5
	var head: Vector2 = look["head"]
	var tail: Vector2 = look["tail"]
	var lamp: float = look["lamp"]
	var roof: Vector2 = look["roof"]
	var spots := {
		"head lamp": [
			Vector2(half.x - lamp * 0.5 - 1.5, (head.x + head.y) * 0.5),
			VehicleArtConfig.headlight_color,
		],
		"tail lamp": [
			Vector2(-half.x + 0.25 + lamp * 0.5, (tail.x + tail.y) * 0.5),
			VehicleArtConfig.tail_off_color,
		],
		"roof": [Vector2((roof.x + roof.y) * 0.5 - 6.0, 4.0), BLUE],
	}
	for what: String in spots:
		var at := _mesh_texel(length_width, spots[what][0])
		var seen := image.get_pixel(at.x, at.y)
		t.check(
			_near(seen, spots[what][1]),
			"%s: the %s lies where the mesh has it (%s)" % [kind, what, seen],
		)


## A door skin lies where the leaf does: it holds the leaf's span about its hinge.
func _door_skin(t: TestContext) -> void:
	for kind: StringName in [&"car", &"van"]:
		for def: Dictionary in VehicleConfig.kinds[kind]["doors"]:
			var skin := VehicleSkin.door(kind, def, BLUE)
			var image := (skin["texture"] as Texture2D).get_image()
			var rect: Rect2 = skin["rect"]
			var depth: float = VehicleConfig.looks[kind]["door_depth"]
			var frame := VehicleMesh._span(def, depth, false)
			var around := Rect2(frame.position - def["hinge"], frame.size)
			t.check(
				rect.grow(0.51).encloses(around),
				"%s %s: its skin %s holds its leaf %s" % [kind, def["id"], rect, around],
			)
			t.expect_near(
				image.get_size().x, rect.size.x, 0.6, "%s %s: texel a px (x)" % [kind, def["id"]]
			)
			t.expect_near(
				image.get_size().y, rect.size.y, 0.6, "%s %s: texel a px (y)" % [kind, def["id"]]
			)


## A skin is made once per kind and paint (and door): asking again gives the one texture.
func _cached(t: TestContext) -> void:
	var held := VehicleSkin.count()
	var first: Dictionary = VehicleSkin.body(&"car", BLUE)
	var again: Dictionary = VehicleSkin.body(&"car", BLUE)
	t.check(first["texture"] == again["texture"], "a body skin is held, not remade")
	var def: Dictionary = VehicleConfig.kinds[&"car"]["doors"][0]
	t.check(
		VehicleSkin.door(
			&"car",
			def,
			BLUE,
		)["texture"] == VehicleSkin.door(&"car", def, BLUE)["texture"],
		"a door skin is held too",
	)
	t.expect_eq(VehicleSkin.count(), held, "asking again adds no skin")
	VehicleSkin.body(&"car", Color.GREEN)
	t.expect_eq(VehicleSkin.count(), held + 1, "another paint is another skin")


## The canvas-canonical size of a kind's body (width across, length along).
func _canonical(kind: StringName) -> Vector2:
	var size: Vector2 = VehicleConfig.kinds[kind]["size"]
	return Vector2(size.y, size.x)


## The canvas pixel of vehicle-frame point `p` on a canonical canvas of `size` (`Art.at`).
func _texel(size: Vector2, p: Vector2) -> Vector2i:
	return Vector2i(roundi(size.x * 0.5 - p.y), roundi(size.y * 0.5 + p.x))


## The texel of the mesh-frame skin (length across, x forward) for vehicle-frame point `p`.
func _mesh_texel(length_width: Vector2, p: Vector2) -> Vector2i:
	var at := p + length_width * 0.5
	return Vector2i(
		clampi(floori(at.x), 0, int(length_width.x) - 1),
		clampi(floori(at.y), 0, int(length_width.y) - 1),
	)


## How many pixels of `image` are `colour`.
func _count(image: Image, colour: Color) -> int:
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			if PixelCanvas._same(image.get_pixel(x, y), colour):
				n += 1
	return n


## The van's sliding door.
func _slide_door() -> Dictionary:
	for def: Dictionary in VehicleConfig.kinds[&"van"]["doors"]:
		if def["kind"] == &"slide":
			return def
	return {}


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.06
