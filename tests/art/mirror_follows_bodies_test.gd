extends GameTest
## The 3D mirror follows the 2D sim (#193 rule 3, G9; Art's `WorldMirror`, interface 27). In a small
## world (a walled arena with a floor, an armchair and two characters) the mirror gives every drawn
## body a proxy of its own sized from its collision shape: walls full height, the floor flat, a
## character a capsule, the armchair a box of a plausible height; 2D `(x, y)` lands at 3D
## `(x, 0, y)` at ONE scale (`RenderConfig.unit`, set to 0.5 here so a wrong or missing scale shows)
## and a body's turn is the proxy's turn about the up axis. It follows what moves, writes only what
## changed, leaves a sleeping rigid body alone, grows a proxy for a body that spawns, drops the
## proxies of one that despawns, and hides a character who died (the ragdoll's mirror is a later
## job). Read off the mirror's public members (`proxies_of`, `count`, `followed`, `written`) and the
## proxies' world boxes; expected places and sizes are worked from the 2D bodies, not from the
## mirror's code.

const ARENA := Rect2(0, 0, 800, 500)
const SCALE := 0.5
const CHAIR_AT := Vector2(600, 400)
const SPAWN_AT := Vector2(300, 400)
const SPAWN_SIZE := Vector2(60, 24)

var _view: SubViewport
var _mirror: Node3D


func describe() -> Dictionary:
	return {
		"name": "The 3D mirror follows the 2D bodies: place, turn, spawn, despawn, sleep",
		"description": "Each body gets a proxy sized from its collision shape at (x, 0, y) times "
			+ "one scale; what moves is followed, a sleeping rigid body is skipped, a spawned body "
			+ "gets a proxy and a despawned one loses it.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.object(&"chair", "armchair", CHAIR_AT)
	s.actor(&"a", &"puppet", Vector2(200, 250))
	s.actor(&"b", &"puppet", Vector2(300, 150))
	s.set_static(RenderConfig, &"unit", SCALE)


func run(t: TestContext) -> void:
	await t.frames(90)  # the armchair settles and falls asleep
	_view = SubViewport.new()
	_view.own_world_3d = true
	t.world.add_child(_view)
	_mirror = WorldMirror.new()
	_view.add_child(_mirror)
	_mirror.mirror(t.world)
	await t.frames(3)
	_check_places_and_sizes(t)
	await _check_sleeping_and_following(t)
	await _check_turning(t)
	await _check_spawn_and_despawn(t)
	await _check_death(t)


## The world box of a proxy: where it stands and how big it is, in 3D units.
func _box(proxy: Node3D) -> AABB:
	return proxy.global_transform * (proxy as MeshInstance3D).get_aabb()


## The enabled collision shapes directly under `body`.
func _shapes_of(body: Node) -> Array:
	return body.get_children().filter(func(c): return c is CollisionShape2D and not c.disabled)


## The 2D footprint a collision shape covers, in 2D pixels, read off the shape itself.
func _footprint(shape: Shape2D) -> Vector2:
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size
	if shape is CircleShape2D:
		return Vector2.ONE * (shape as CircleShape2D).radius * 2.0
	return Vector2.ZERO


func _first_proxy(t: TestContext, body: Node, what: String) -> Node3D:
	var proxies: Array = _mirror.proxies_of(body)
	if not t.require(not proxies.is_empty(), "%s has a proxy" % what):
		return null
	return proxies[0]


## Every kind is placed at (x, 0, y) times the scale on the ground and sized from its shape.
func _check_places_and_sizes(t: TestContext) -> void:
	var walker := _first_proxy(t, t.actor(&"a"), "the character")
	var seat := _first_proxy(t, t.object(&"chair"), "the armchair")
	if walker == null or seat == null:
		return
	var walker_box := _box(walker)
	var seat_box := _box(seat)
	var middle := walker_box.get_center()
	t.expect_near(middle.x, 200.0 * SCALE, 0.5, "the character stands at x * scale")
	t.expect_near(middle.z, 250.0 * SCALE, 0.5, "the character stands at y * scale")
	t.expect_near(walker_box.position.y, 0.0, 0.3, "the character stands on the ground plane")
	t.check(
		walker is MeshInstance3D and (walker as MeshInstance3D).mesh is CapsuleMesh,
		"a character is a capsule",
	)
	_check_armchair(t, t.object(&"chair"), seat_box)
	_check_heights(t, walker_box, seat_box)
	_check_floor(t)


## The armchair's box is where and as big as its shape, scaled, on the ground.
func _check_armchair(t: TestContext, chair: Node, seat_box: AABB) -> void:
	var size := _footprint(_shapes_of(chair)[0].shape)
	var middle := seat_box.get_center()
	t.expect_near(middle.x, CHAIR_AT.x * SCALE, 1.0, "the armchair is at x * scale")
	t.expect_near(middle.z, CHAIR_AT.y * SCALE, 1.0, "the armchair is at y * scale")
	t.expect_near(seat_box.size.x, size.x * SCALE, 1.0, "its width is its shape's, scaled")
	t.expect_near(seat_box.size.z, size.y * SCALE, 1.0, "its depth is its shape's, scaled")
	t.expect_near(seat_box.position.y, 0.0, 0.3, "the armchair stands on the ground")


## Walls stand full height, over a character, over an armchair, which has a height of its own.
func _check_heights(t: TestContext, walker_box: AABB, seat_box: AABB) -> void:
	var wall_top := _tallest_wall(t)
	t.check(
		wall_top > walker_box.size.y,
		"walls (%.0f) stand taller than a character (%.0f)" % [wall_top, walker_box.size.y],
	)
	t.check(
		walker_box.size.y > seat_box.size.y,
		"a character (%.0f) is taller than an armchair (%.0f)" % [
			walker_box.size.y,
			seat_box.size.y,
		],
	)
	t.check(seat_box.size.y > 4.0 * SCALE, "an armchair has a height of its own")


## The floor is a flat slab over its room.
func _check_floor(t: TestContext) -> void:
	var floors := t.world.get_tree().get_nodes_in_group(&"floors")
	if not t.require(not floors.is_empty(), "premise: the arena has a floor"):
		return
	var slab := _first_proxy(t, floors[0], "the floor")
	if slab == null:
		return
	var box := _box(slab)
	var rect := Rect2((floors[0] as Node2D).global_position, floors[0].get("size"))
	t.check(box.size.y < 4.0, "the floor is flat (%.1f units thick)" % box.size.y)
	t.expect_near(box.size.x, rect.size.x * SCALE, 1.0, "the floor spans its room")
	t.expect_near(box.get_center().x, rect.get_center().x * SCALE, 1.0, "at its place")


## The tallest proxy among the world's static bodies (the arena's walls), in 3D units.
func _tallest_wall(t: TestContext) -> float:
	var tallest := 0.0
	for body: Node in t.world.find_children("*", "StaticBody2D", true, false):
		for proxy: Node3D in _mirror.proxies_of(body):
			tallest = maxf(tallest, _box(proxy).size.y)
	return tallest


## A sleeping rigid body is not read; what moves is written once per change and the proxy lands
## where its body ends.
func _check_sleeping_and_following(t: TestContext) -> void:
	var chair := t.object(&"chair") as RigidBody2D
	if not t.require(chair != null and chair.sleeping, "premise: the armchair is asleep"):
		return
	var moving := _moving_shapes(t)
	t.expect_eq(_mirror.followed, moving, "an update reads the moving proxies, not the sleeper's")
	await t.frames(2)
	t.expect_eq(_mirror.written, 0, "a still world is written to not at all")
	var character := t.actor(&"b") as Node2D
	var to := Vector2(420, 120)
	character.global_position = to
	await t.frames(2)
	var walker := _first_proxy(t, character, "the moved character")
	if walker != null:
		t.expect_near(
			_box(walker).get_center().x,
			to.x * SCALE,
			0.5,
			"a moved character is followed (x)",
		)
		t.expect_near(
			_box(walker).get_center().z,
			to.y * SCALE,
			0.5,
			"a moved character is followed (z)",
		)
	chair.apply_central_impulse(Vector2(-6000, 0))
	await t.frames(6)
	t.check(_mirror.followed == moving + 1, "an awake armchair is followed again")
	t.require(await t.until(func(): return chair.sleeping, 6.0), "premise: it comes to rest")
	await t.frames(2)
	var seat := _first_proxy(t, chair, "the armchair")
	if seat != null:
		t.expect_near(_box(seat).get_center().x, chair.global_position.x * SCALE, 1.0,
			"the armchair's proxy goes where the armchair went")
		t.check(chair.global_position.x < CHAIR_AT.x - 2.0, "premise: the armchair slid")


## How many enabled collision shapes sit under the world's characters: the moving proxies that are
## never asleep.
func _moving_shapes(t: TestContext) -> int:
	var n := 0
	for body: Node in t.world.get_tree().get_nodes_in_group(&"characters"):
		for child in body.get_children():
			var shape := child as CollisionShape2D
			if shape != null and not shape.disabled and shape.shape != null:
				n += 1
	return n


## A box (a door's kind of body, moved by hand) turned by 0.9 rad about the 2D plane is turned the
## same way about the up axis: its local x axis (cos, 0, sin).
func _check_turning(t: TestContext) -> void:
	var body := _spawn(t, SPAWN_AT, true)
	await t.frames(3)
	body.rotation = 0.9
	await t.frames(3)
	var proxy := _first_proxy(t, body, "the spawned box")
	if proxy == null:
		return
	var along := proxy.global_transform.basis.x.normalized()
	t.expect_near(along.x, cos(0.9), 0.02, "a turned body's proxy is turned (x)")
	t.expect_near(along.y, 0.0, 0.02, "it stays upright")
	t.expect_near(along.z, sin(0.9), 0.02, "a turned body's proxy is turned (z)")
	body.queue_free()
	await t.frames(3)


## A body that spawns after the mirror started gets a proxy; one that despawns loses it.
func _check_spawn_and_despawn(t: TestContext) -> void:
	var before: int = _mirror.count
	var body := _spawn(t, SPAWN_AT + Vector2(100, 0))
	await t.frames(3)
	var proxies: Array = _mirror.proxies_of(body)
	t.expect_eq(proxies.size(), 1, "a spawned body gets a proxy")
	t.expect_eq(_mirror.count, before + 1, "and the count grows by one")
	if proxies.size() == 1:
		var seat := _box(proxies[0])
		t.expect_near(seat.get_center().x, (SPAWN_AT.x + 100.0) * SCALE, 0.5, "where it spawned")
		t.expect_near(seat.size.x, SPAWN_SIZE.x * SCALE, 0.5, "as big as its shape")
		t.expect_near(seat.size.z, SPAWN_SIZE.y * SCALE, 0.5, "as deep as its shape")
	body.queue_free()
	await t.frames(3)
	t.check(
		proxies.all(func(p): return not is_instance_valid(p)),
		"a despawned body's proxy is freed",
	)
	t.expect_eq(_mirror.count, before, "and the count drops back")
	var left := 0
	for child in _mirror.get_children():
		left += 1
	t.expect_eq(left, before, "the proxy node itself is gone, not hidden")


## A character who dies no longer stands in the 3D view.
func _check_death(t: TestContext) -> void:
	var character := t.actor(&"a")
	var walker := _first_proxy(t, character, "the character")
	if walker == null:
		return
	t.check(walker.visible, "premise: the living character's proxy shows")
	character.take_damage(1000.0)
	await t.frames(2)
	t.check(not walker.visible, "a dead character's proxy is hidden")


## A free-standing box of `SPAWN_SIZE` at `at` (a rigid body, or one moved by hand), added to the
## world as the sim spawns bodies.
func _spawn(t: TestContext, at: Vector2, by_hand := false) -> PhysicsBody2D:
	var body: PhysicsBody2D
	if by_hand:
		body = AnimatableBody2D.new()
	else:
		var rigid := RigidBody2D.new()
		rigid.gravity_scale = 0.0
		body = rigid
	body.position = at
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = SPAWN_SIZE
	shape.shape = box
	body.add_child(shape)
	t.world.add_child(body)
	return body
