extends GameTest
## D12 (#194): blood lands where the 3D surface is. A round that goes through a body at chest height
## beside a wall throws blood out of the far side along its flight: it marks the wall's face at
## about that height (the mark stands on the wall, a few px up),
## and blood sprayed at a desk's top lands on the top (31 px up).

const SCRATCH := "user://settings_blood_wall_height_test.json"
## The chest height (px) the round meets the body at.
const CHEST := 50.0
const BODY := Vector2(24, 200)
const DESK := Vector2(300, 100)
const HALF := Vector2(60, 25)
const TOP := 31.0
## A mark floats this far (px) off the face it lies on (the decal rule's layer lift).
const FILM := 2.5


func describe() -> Dictionary:
	return {
		"name": "Blood marks the wall at the hit's height and the desk at its top",
		"description": "The blood a round throws out of a body at chest height beside the west "
			+ "wall stands on the wall's face near that height; blood sprayed at a desk's top "
			+ "lands on the top.",
		"tags": ["blood", "physics", "3d", "wall", "furniture", "heights"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", true)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.object(&"desk", "desk", DESK)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror)
	mirror.mirror(t.world)
	await t.frames(3)
	var face := _wall_face(t)
	if not t.require(face > 0.0, "premise: the west wall's face is found (x %.1f)" % face):
		return
	await _check_wall(t, layer, face)
	await _check_top(t, layer)
	await _check_end_face(t, layer)


## A shot through a body 8 px off the wall, flying at it: its exit blood marks the wall.
func _check_wall(t: TestContext, layer: FxLayer, face: float) -> void:
	var hit := HitInfo.new()
	hit.position = BODY
	hit.normal = Vector2.RIGHT
	hit.direction = Vector2.LEFT
	hit.has_exit = true
	hit.exit_position = Vector2(face + 8.0, BODY.y)
	hit.exit_normal = Vector2.LEFT
	hit.damage = 40.0
	hit.height = CHEST
	_wound(t, BODY).record(hit)
	await t.frames(4)
	var on_wall := _marks_where(layer, func(v: Vector3) -> bool: return absf(v.x - face) < FILM)
	if not t.require(not on_wall.is_empty(), "the exit blood marks the wall's face"):
		return
	for mark in on_wall:
		var low := INF
		var high := -INF
		for v in mark.verts:
			low = minf(low, v.y)
			high = maxf(high, v.y)
		t.check(
			high > CHEST - 15.0 and high <= CHEST + 15.0 + 0.5,
			"it stands on the wall near the hit's height (top %.1f, bottom %.1f)" % [high, low],
		)
		var faces_out := mark.normals.size() == mark.verts.size()
		for n in mark.normals:
			faces_out = faces_out and n.is_equal_approx(Vector3.RIGHT)
		t.check(faces_out, "it faces out of the wall, into the room")
		t.check(low > 20.0, "none of it is down on the floor (lowest %.1f)" % low)
	# The exit blood lands at (face + 8, BODY.y): were it a floor splat its core would be centred
	# there. The spray at the wound, 18 px off the wall, may leave a spike or a droplet on the floor
	# by the wall: that is the floor's blood, not this one.
	var exit_at := Vector2(face + 8.0, BODY.y)
	var dropped := layer.ink.marks(InkMark.Kind.SPLAT).filter(
		func(m: InkMark) -> bool: return _on_floor(m) and _centre(m).distance_to(exit_at) < 4.0
	)
	t.expect_eq(
		dropped.size(),
		0,
		"the blood that marked the wall left no splat on the floor where it struck",
	)


## A hit's spray, thrown at the desk's top from a body at its end: it lands on the top.
func _check_top(t: TestContext, layer: FxLayer) -> void:
	var hit := HitInfo.new()
	hit.position = DESK + Vector2(HALF.x + 12.0, 0.0)
	hit.normal = Vector2.LEFT
	hit.direction = Vector2.RIGHT
	hit.damage = 40.0
	hit.height = CHEST
	var wound := _wound(t, hit.position + Vector2(6, 0))
	for _i in 3:  # the spray's reach is random: any one of them may fall short of the desk
		wound.record(hit)
	await t.frames(4)
	var on_top := _marks_where(
		layer,
		func(v: Vector3) -> bool: return absf(v.y - TOP) < 4.0 and _over_desk(v),
	)
	t.check(
		not on_top.is_empty(),
		"blood sprayed at the desk lands on its top (%d marks)" % on_top.size(),
	)
	var under := _marks_where(
		layer,
		func(v: Vector3) -> bool: return v.y < 3.0 and _inside_desk(v),
	)
	t.expect_eq(
		under.size(),
		0,
		"no blood lies on the floor under the desk's top (a floor splat is moved off its edge)",
	)


## A round's exit blood met the desk's east end near its top (28 px up, the top 31): it stands on
## the end face and is cut off at the desk's top, not at a wall's height.
func _check_end_face(t: TestContext, layer: FxLayer) -> void:
	var edge := DESK.x + HALF.x
	var hit := HitInfo.new()
	hit.position = Vector2(edge + 20.0, DESK.y)
	hit.normal = Vector2.RIGHT
	hit.direction = Vector2.LEFT
	hit.has_exit = true
	hit.exit_position = Vector2(edge + 6.0, DESK.y)
	hit.exit_normal = Vector2.LEFT
	hit.damage = 40.0
	hit.height = TOP - 3.0
	for _i in 4:
		_wound(t, hit.position).record(hit)
	await t.frames(4)
	var on_end := false
	var highest := -INF
	for mark in layer.ink.marks(InkMark.Kind.SPLAT):
		if mark.normals.size() != mark.verts.size():
			continue
		for i in mark.verts.size():
			var on_face := absf(mark.verts[i].x - edge) < FILM
			if on_face and mark.normals[i].is_equal_approx(Vector3.RIGHT):
				on_end = true
				highest = maxf(highest, mark.verts[i].y)
	if not t.require(on_end, "the blood stands on the desk's east end face"):
		return
	t.check(
		highest <= TOP + 0.5,
		"it is cut off at the desk's top (%.1f px), not a wall's height (highest %.1f)"
			% [TOP, highest],
	)


## Whether the point `v` is over the desk's footprint.
func _over_desk(v: Vector3) -> bool:
	return absf(v.x - DESK.x) <= HALF.x and absf(v.z - DESK.y) <= HALF.y


## Whether the point `v` is inside the desk's footprint, `FILM` in from its edge.
func _inside_desk(v: Vector3) -> bool:
	return absf(v.x - DESK.x) < HALF.x - FILM and absf(v.z - DESK.y) < HALF.y - FILM


## Whether the mark lies on the floor (all of it under 3 px), and the plan point of its middle.
func _on_floor(mark: InkMark) -> bool:
	for v in mark.verts:
		if v.y >= 3.0:
			return false
	return true


func _centre(mark: InkMark) -> Vector2:
	var sum := Vector2.ZERO
	for v in mark.verts:
		sum += Vector2(v.x, v.z)
	return sum / float(mark.verts.size())


## The splat marks with a vertex `where` says yes to.
func _marks_where(layer: FxLayer, where: Callable) -> Array[InkMark]:
	var out: Array[InkMark] = []
	for mark in layer.ink.marks(InkMark.Kind.SPLAT):
		for v in mark.verts:
			if where.call(v):
				out.append(mark)
				break
	return out


## A body (a plain node) at `at` with a wound, in the world.
func _wound(t: TestContext, at: Vector2) -> BloodWound:
	var host := Node2D.new()
	host.position = at
	t.world.add_child(host)
	var wound := BloodWound.new()
	host.add_child(wound)
	return wound


## Where the west wall's face is (px): a ray along the floor plan at chest height, west.
func _wall_face(t: TestContext) -> float:
	var space := TwinSpace.space_of(t.world)
	var from := PlanSpace.lift(Vector2(40.0, BODY.y), CHEST)
	var to := PlanSpace.lift(Vector2(-40.0, BODY.y), CHEST)
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.TWIN_WORLD)
	var hit := space.intersect_ray(query)
	return hit["position"].x if not hit.is_empty() else -1.0


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
