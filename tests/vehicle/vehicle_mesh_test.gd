extends GameTest
## The 3D mesh of a car and a van (#193 phase 2, Vehicles; `domain-art/meshes.md`): Vehicles
## registers a builder under the mirror's vehicle kind and the mirror shows each vehicle by a
## kit-built body in place of its proxy box. The hull is the kind's footprint, stands at the
## how-to's heights (a car 36 px at the belt and 52 at the roof, a van 46 and 78), carries the
## vehicle's paint and shares one `Mesh` with every vehicle of its kind and paint; four wheels stand
## on their sides at the axles and the front pair steer; each door's leaf follows the 2D door (a
## swing door's free edge where the
## 2D handle is, a sliding door rolled back); the tail lamps glow while it brakes; a bullet's dent
## shows as a patch. Expected numbers are the spec's (the how-to's heights, the kind's own row), a
## copy of them, not read back from the holder; at half scale every length halves.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_vehicle_mesh_test.json"
const CAR_AT := Vector2(300, 250)
const TURNED_AT := Vector2(700, 250)
const VAN_AT := Vector2(500, 600)
const TURN := 0.5
const BLUE := Color(0.15, 0.25, 0.7)
## Per kind: [belt, roof] heights (px) and the footprint (length, width).
const CAR := { "belt": 36.0, "roof": 52.0, "size": Vector2(220, 110), "sill": 9.0 }
const VAN := { "belt": 46.0, "roof": 78.0, "size": Vector2(260, 125), "sill": 11.0 }
const MATCH := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "A car and a van are shown by kit-built meshes, not their proxy boxes",
		"description": "Vehicles' builder gives each a hull at its footprint and height in its "
			+ "paint, four wheels that steer and turn, door leaves that follow the 2D doors, tail "
			+ "lamps that glow when braking and dent patches; meshes shared by kind and paint; "
			+ "Main's 3D view registers it.",
		"tags": ["mirror", "3d", "render", "meshkit", "vehicle"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 1000, 800), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.vehicle(&"twin", &"car", Vector2(300, 480))
	s.vehicle(&"blue", &"car", Vector2(300, 700), 0.0, { "color": BLUE })
	s.vehicle(&"turned", &"car", TURNED_AT, TURN)
	s.vehicle(&"van", &"van", VAN_AT)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(5)
	var mirror := _mirror(t)
	VehicleMeshes.register(mirror.builders)
	var materials := ToonMaterial.textured_count()
	mirror.mirror(t.world)
	await t.frames(3)
	var car := t.vehicle(&"car") as Node2D
	var van := t.vehicle(&"van") as Node2D
	var rig := _rig_of(mirror, car)
	var van_rig := _rig_of(mirror, van)
	if not t.require(rig != null and van_rig != null, "a car and a van are shown by a mesh rig"):
		return
	_check_hull(t, rig, car, CAR, 1.0)
	_check_hull(t, van_rig, van, VAN, 1.0)
	_check_sharing(t, mirror, rig)
	_check_leaves(t, rig, car, materials)
	_check_wheels(t, rig, car)
	_check_wheels(t, van_rig, van)
	_check_turned(t, mirror)
	await _check_steering(t, rig, car)
	await _check_doors(t, rig, car)
	await _check_sliding_door(t, van_rig, van)
	await _check_lamps(t, rig, car)
	await _check_dents(t, rig, car)
	await _check_door_dent(t, rig, car)
	await _check_scale(t, car)
	await _check_main(t)


## The rig the mirror shows `body` by, when it is one of ours.
func _rig_of(mirror: WorldMirror, body: Node) -> VehicleMeshRig:
	var shown := mirror.proxies_of(body)
	if shown.size() == 1 and shown[0] is VehicleMeshRig:
		return shown[0] as VehicleMeshRig
	return null


## The hull's mesh node.
func _hull(rig: VehicleMeshRig) -> MeshInstance3D:
	return rig.hull


## The hull at the kind's footprint and heights, standing on its sill, centred on the body.
func _check_hull(t: TestContext, rig: VehicleMeshRig, body: Node2D, spec: Dictionary,
		factor: float) -> void:
	var box := _hull(rig).mesh.get_aabb()
	var size: Vector2 = spec["size"]
	t.expect_near(box.size.x, size.x * factor, 2.5 * factor, "as long as the body (x%.1f)" % factor)
	t.expect_near(box.size.z, size.y * factor, 2.5 * factor, "as wide as the body (x%.1f)" % factor)
	t.expect_near(
		box.end.y,
		float(spec["roof"]) * factor,
		0.01,
		"its roof stands at %s px" % spec["roof"],
	)
	t.expect_near(box.position.y, float(spec["sill"]) * factor, 0.01, "its underside is the sill")
	t.expect_near(box.get_center().x, 0.0, 2.0 * factor, "centred on the body (x)")
	t.expect_near(box.get_center().z, 0.0, 2.0 * factor, "centred on the body (z)")
	var white := true
	var arrays := (_hull(rig).mesh as ArrayMesh).surface_get_arrays(0)
	for colour: Color in arrays[Mesh.ARRAY_COLOR]:
		white = white and colour.is_equal_approx(Color.WHITE)
	t.check(white, "every face is white: the art is the texture's, the shape the mesh's")
	var skin := VehicleSkin.body(body.get("kind"), body.get("color"))
	t.check(
		_hull(rig).material_override == ToonMaterial.textured(skin["texture"], false),
		"it wears the 2D art of its kind and paint (the textured toon)",
	)
	var rect: Vector4 = Vector4(
		(skin["rect"] as Rect2).position.x * factor,
		(skin["rect"] as Rect2).position.y * factor,
		(skin["rect"] as Rect2).size.x * factor,
		(skin["rect"] as Rect2).size.y * factor,
	)
	var set_rect: Vector4 = _hull(rig).get_instance_shader_parameter(&"uv_rect")
	t.check(
		set_rect.is_equal_approx(rect), "the art covers the body's footprint (%s)" % set_rect
	)


## Vehicles of one kind share one hull mesh; one paint shares a texture, another has its own.
func _check_sharing(t: TestContext, mirror: WorldMirror, rig: VehicleMeshRig) -> void:
	var twin := _rig_of(mirror, t.vehicle(&"twin"))
	var blue := _rig_of(mirror, t.vehicle(&"blue"))
	t.check(
		twin != null and _hull(twin).mesh == _hull(rig).mesh,
		"two cars of one paint share the one hull mesh",
	)
	t.check(
		twin != null and _hull(twin).material_override == _hull(rig).material_override,
		"and the one textured material",
	)
	t.check(
		blue != null and _hull(blue).mesh == _hull(rig).mesh,
		"a car of another paint shares the mesh (the paint is in the texture)",
	)
	if blue != null:
		t.check(
			_hull(blue).material_override != _hull(rig).material_override,
			"but has a texture and material of its own",
		)
		var image := (VehicleSkin.body(&"car", BLUE)["texture"] as Texture2D).get_image()
		var found := false
		for y in image.get_height():
			for x in image.get_width():
				found = found or _near(image.get_pixel(x, y), BLUE)
		t.check(found, "and it is painted in that paint")


## Each door leaf wears its own panel's 2D art, and the textured materials are one per texture:
## a hull and a leaf each, per kind and paint (two cars and a van here), not per vehicle.
func _check_leaves(t: TestContext, rig: VehicleMeshRig, car: Node2D, before: int) -> void:
	for def: Dictionary in VehicleConfig.kinds[&"car"]["doors"]:
		var skin := VehicleSkin.door(&"car", def, car.get("color"))
		var leaf: MeshInstance3D = rig.doors[def["id"]]["node"]
		t.check(
			leaf.material_override == ToonMaterial.textured(skin["texture"], false),
			"the %s leaf wears its panel's art" % def["id"],
		)
		var front: bool = (VehicleConfig.looks[&"car"]["mirror"] as Array).has(def["id"])
		t.expect_eq(
			leaf.get_node_or_null("MirrorArt") != null, front, "%s: a mirror's art" % def["id"]
		)
	# two cars of a paint, another paint and a van were built here: a hull and a leaf each per
	# kind and paint (a car 5, a van 6), not per vehicle (three red cars would make it 26)
	var added := ToonMaterial.textured_count() - before
	t.check(
		added >= 5 and added <= 16,
		"textured materials are one per kind, paint and part, not per vehicle (+%d)" % added,
	)


## Four wheels on their sides at the axles, as wide as the 2D wheel is long across the axle, as tall
## as it is long, standing on the ground.
func _check_wheels(t: TestContext, rig: VehicleMeshRig, body: Node2D) -> void:
	var row: Dictionary = VehicleConfig.kinds[body.get("kind")]
	var size: Vector2 = row["wheel_size"]
	t.expect_eq(rig.wheels.size(), 4, "four wheels")
	for wheel in rig.wheels:
		var box: AABB = (wheel as MeshInstance3D).mesh.get_aabb()
		t.expect_near(box.size.y, size.x, 0.01, "a wheel is its diameter tall")
		t.expect_near(box.size.x, size.x, 0.01, "and its diameter long")
		t.expect_near(
			box.size.z,
			size.y + 4.0 * VehicleMeshConfig.proud,
			0.2,
			"its axle across the body",
		)
		var pivot := wheel.get_parent() as Node3D
		t.expect_near(pivot.position.y, size.x * 0.5, 0.01, "it stands on the ground")
		var at := Vector2(pivot.global_position.x, pivot.global_position.z)
		var local: Vector2 = body.to_local(at)
		var axles: Array = [row["axle_front"], row["axle_rear"]]
		var axle := axles.any(func(x: float) -> bool: return absf(local.x - x) < 1.0)
		t.check(axle, "a wheel stands at an axle (x %s)" % local.x)


## A turned vehicle carries its mesh round with it.
func _check_turned(t: TestContext, mirror: WorldMirror) -> void:
	var rig := _rig_of(mirror, t.vehicle(&"turned"))
	if not t.require(rig != null, "a turned car is shown by a mesh"):
		return
	var nose := rig.global_transform.basis * Vector3.RIGHT
	t.expect_near(nose.x, cos(TURN), 0.01, "its nose turns with the body (x)")
	t.expect_near(nose.z, sin(TURN), 0.01, "its nose turns with the body (z)")


## The front pair steer by the 2D steering angle, the rear pair do not.
func _check_steering(t: TestContext, rig: VehicleMeshRig, car: Node2D) -> void:
	var front: Node3D = rig.front[0]
	t.check(
		await t.until(func() -> bool:
			car.drive.wheel_angle = 0.5
			return front.rotation.y < -0.2, 2.0),
		"the front wheels steer with the 2D steering angle",
	)
	for wheel in rig.wheels:
		var pivot := wheel.get_parent() as Node3D
		if not rig.front.has(pivot):
			t.expect_near(pivot.rotation.y, 0.0, 0.001, "a rear wheel does not steer")
	car.drive.wheel_angle = 0.0


## Each door's leaf follows its 2D door: shut it sits at the hinge, open its free edge is where the
## 2D handle is.
func _check_doors(t: TestContext, rig: VehicleMeshRig, car: Node2D) -> void:
	t.expect_eq(rig.doors.size(), 4, "a leaf for each of the car's four doors")
	var door: Variant = car.cabin.door(&"front_left")
	var leaf: Node3D = rig.doors[&"front_left"]["node"]
	var before := leaf.global_position
	t.expect_near(leaf.rotation.y, 0.0, 0.001, "a shut door is not turned")
	door.open()
	t.check(await t.until(func() -> bool: return door.is_open(), 3.0), "the 2D door opens")
	await t.frames(3)
	var angle: float = door.angle()
	t.check(absf(angle) > 1.0, "the 2D door is wide open (%s)" % angle)
	var pane: GeometryInstance3D = rig.doors[&"front_left"]["pane"]
	t.check(not pane.visible, "its window is gone with it (the glass pane faded out)")
	t.expect_near(leaf.rotation.y, -angle, 0.001, "the leaf is turned as far")
	t.expect_near(leaf.global_position.x, before.x, 0.01, "about its hinge (x)")
	var hinge: Vector2 = door.hinge
	var handle: Vector2 = VehicleConfig.kinds[&"car"]["doors"][0]["handle"]
	var edge := leaf.global_transform * (Vector3((handle.x - hinge.x), 0.0, (handle.y - hinge.y)))
	var want: Vector2 = car.to_global(door.handle_now())
	t.expect_near(edge.x, want.x, 1.0, "its free edge is where the 2D handle is (x)")
	t.expect_near(edge.z, want.y, 1.0, "its free edge is where the 2D handle is (z)")
	door.close()
	t.check(await t.until(func() -> bool: return door.amount() == 0.0, 3.0), "the door shuts")
	await t.frames(3)
	t.expect_near(leaf.rotation.y, 0.0, 0.001, "and the leaf with it")
	t.check(pane.visible, "and its window is back")
	var fade: float = pane.get_instance_shader_parameter(&"fade")
	t.expect_near(fade, 1.0, 0.001, "whole")


## A sliding door rolls back along the body with the 2D door.
func _check_sliding_door(t: TestContext, rig: VehicleMeshRig, van: Node2D) -> void:
	var door: Variant = van.cabin.door(&"side")
	var leaf: Node3D = rig.doors[&"side"]["node"]
	var shut := leaf.position.x
	door.open()
	t.check(await t.until(func() -> bool: return door.is_open(), 3.0), "the sliding door opens")
	await t.frames(3)
	var rolled: float = door.offset().x
	t.check(rolled < -30.0, "the 2D door rolled back (%s)" % rolled)
	t.expect_near(leaf.position.x, shut + rolled, 0.01, "the leaf rolled back with it")
	door.close()
	await t.until(func() -> bool: return door.amount() == 0.0, 3.0)


## The tail lamps glow while the vehicle brakes, and not otherwise.
func _check_lamps(t: TestContext, rig: VehicleMeshRig, car: Node2D) -> void:
	var emissive: Color = rig.tail.get_instance_shader_parameter(&"emissive")
	t.expect_near(emissive.a, 0.0, 0.001, "the tail lamps are dark at rest")
	t.check(
		await t.until(func() -> bool:
			car.drive.braking = true
			var glow: Color = rig.tail.get_instance_shader_parameter(&"emissive")
			return glow.a > 0.5, 2.0),
		"the tail lamps glow while braking",
	)
	car.drive.braking = false
	t.check(
		await t.until(func() -> bool:
			var glow: Color = rig.tail.get_instance_shader_parameter(&"emissive")
			return glow.a < 0.01, 2.0),
		"and go dark when it stops braking",
	)
	var box: AABB = (rig.tail as MeshInstance3D).mesh.get_aabb()
	t.check(box.size.x < 12.0 and box.size.y < 12.0, "a lamp is a small face (%s)" % box.size)


## A bullet's dent shows as a patch on the body and the cache does not grow with it.
func _check_dents(t: TestContext, rig: VehicleMeshRig, car: Node2D) -> void:
	var dents := rig.get_node("Dents")
	t.expect_eq(dents.get_child_count(), 0, "an untouched car has no dents")
	await _strike(t, car)
	var cached := MeshCache.count()
	await _strike(t, car)
	await _strike(t, car)
	t.expect_eq(dents.get_child_count(), car.hit_marks().size(), "a patch for each dent")
	t.check(dents.get_child_count() >= 3, "three hits leave three patches")
	t.expect_eq(MeshCache.count(), cached, "more dents add nothing to the mesh cache")


## A round hits the car's right side (by default on the fender, clear of every door).
func _strike(t: TestContext, car: Node2D, at := Vector2(60.0, 55.0)) -> void:
	var hit := HitInfo.new()
	hit.position = car.to_global(at)
	hit.normal = Vector2.DOWN
	hit.direction = Vector2.UP
	hit.damage = 20.0
	car.take_hit(hit)
	await t.frames(4)


## A dent in a door follows the leaf: opened, the patch has swung about the hinge with it.
func _check_door_dent(t: TestContext, rig: VehicleMeshRig, car: Node2D) -> void:
	var door: Variant = car.cabin.door(&"front_left")
	var leaf: Node3D = rig.doors[&"front_left"]["node"]
	await _strike(t, car, Vector2(0.0, -55.0))
	var patch: Node3D = null
	for child in leaf.get_children():
		patch = child as Node3D
	if not t.require(patch != null, "a dent in a door's span hangs on its leaf"):
		return
	var hinge := leaf.global_position
	var shut := patch.global_position
	door.open()
	t.check(await t.until(func() -> bool: return door.is_open(), 3.0), "the door opens")
	await t.frames(3)
	var open := patch.global_position
	t.check(open.distance_to(shut) > 10.0, "the patch swung away with the door (%s)" % open)
	t.expect_near(open.distance_to(hinge), shut.distance_to(hinge), 0.5, "about the hinge")
	door.close()
	await t.until(func() -> bool: return door.amount() == 0.0, 3.0)


## At half scale every length of the mesh halves (the one conversion is the kit's).
func _check_scale(t: TestContext, car: Node2D) -> void:
	RenderConfig.unit = 0.5
	var halved := _mirror(t)
	VehicleMeshes.register(halved.builders)
	halved.mirror(t.world)
	await t.frames(3)
	var rig := _rig_of(halved, car)
	if t.require(rig != null, "a car at half scale is shown by a mesh"):
		_check_hull(t, rig, car, CAR, 0.5)


## Main's 3D view registers the vehicle builder.
func _check_main(t: TestContext) -> void:
	RenderConfig.unit = 1.0
	var window := MainProbe.viewport(t)
	var main := MainProbe.open(window)
	MainProbe.setup_menu(main).queue_free()
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	main.add_child(camera)
	var built: Dictionary = await main.start_match(MATCH.duplicate(true))
	if not t.require(not built.is_empty(), "a 3D match started"):
		return
	await t.frames(4)
	var view := main.get_node_or_null("View3D")
	if t.require(view != null, "Main built the 3D view"):
		t.check(
			view.mirror.builders.has(MirrorProxy.VEHICLE),
			"Main's view registers the vehicle's builder",
		)
	await MainProbe.close(t, window)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.04


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
