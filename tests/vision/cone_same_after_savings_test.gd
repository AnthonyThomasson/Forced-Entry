extends GameTest
## V1 cost (`docs/player-vision.md`): the cone's CPU savings change nothing it draws. The cone
## `ViewCone.rebuild` builds is held, vertex for vertex, to the reference cone
## (`tests/_vision/reference_view_cone.gd`), the plainest form of the cone: the same algorithm,
## which keeps nothing from one rebuild to the next and reads and casts everything anew each build.
## Both are asked the same question in the same physics space: one persistent `ViewCone` (so
## whatever it keeps from one rebuild to the next is in play) against one reference, for
## - a grid of eyes and facings in generated houses (a few floorplans and seeds), the cone and the
##   bubble both;
## - a door swung through the cone between two rebuilds, a piece shoved across it and a piece that
##   leaves the world: a hand-laid pair of rooms joined by a doorway, rebuilt after every step.
## The tolerance is `Probe.TOLERANCE` px on every vertex. Nothing but a saving that changes the
## polygon can exceed it: the faster cone does the same float operations on the same numbers, so it
## matches to the last bit, and the tolerance only leaves room for an operation done in another
## order.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Cone := preload("res://scenes/vision/view_cone.gd")
const Reference := preload("res://tests/_vision/reference_view_cone.gd")
## The houses: floorplan and seed.
const HOUSES := [
	["garage_home", 7],
	["starter_home", 3],
	["office_loft", 11],
	["garage_home", 23],
	["bungalow", 5],
	["railroad_flat", 19],
]
## The eyes of a room: this many columns and rows inside it, each this far (px) from its walls at
## least, and the facings (degrees) each looks along: off the axes, so the cone's edge rays are
## never along a wall.
const GRID := 4
const EDGE_MARGIN := 40.0
const FACINGS := [20.0, 80.0, 140.0, 200.0, 260.0, 320.0]
## An eye this near something solid (px) is left out.
const SOLID_MARGIN := 10.0
## The door swings from closed to open in this many steps, a quarter turn, about a hinge on the
## doorway's end; the piece shoved across the room moves in this many steps of this size (px).
const SWING_STEPS := 12
const SHOVE_STEPS := 6
const SHOVE_STEP := Vector2(55.0, 20.0)
const HINGE := Vector2(700.0, 200.0)
const DOOR_LENGTH := 90.0
## The dents: this many volleys, each this many hits at random along the walls and pieces (the
## colliders are rebuilt from the dented polygons: convex pieces, slivers among them).
const HITS_PER_VOLLEY := 50
const SCATTERED := 300
const NEAR := 220.0
## Eyes for the swing: in the living room, in the kitchen, and on the doorway's line.
const SWING_EYES := [
	Vector2(250, 250), Vector2(450, 180), Vector2(500, 330), Vector2(1000, 250), Vector2(900, 120),
	Vector2(600, 100), Vector2(1100, 400),
]
const SWING_FACINGS := [0.0, 25.0, -30.0, 180.0, 160.0, 10.0, 200.0]
## The body that moves in every step of `_compare_moving_body`: this many steps of this size (px).
const MOVING_STEPS := 24
const MOVING_STEP := Vector2(9.0, -6.0)
const SHOVE_AT := Vector2(450, 350)
const SHOVE_EYES := [Vector2(150, 250), Vector2(620, 420)]
## A character in the way: it blocks sight standing (coverage 60) and not crouched (35) for an eye
## that looks over only what is lower than `Probe.LOOK_OVER_LOW`, so its posture changes the polygon
## with no move of its own.
const STANDER_AT := Vector2(400, 250)
const STANDER_EYES := [Vector2(150, 250), Vector2(150, 200), Vector2(250, 300)]
## At least this many rebuilds must be compared, or the test proves nothing.
const MIN_HOUSE_PAIRS := 800
const MIN_SWING_PAIRS := 100
const MIN_DENT_PAIRS := 1500

var _sight := {
	"fov_degrees": Probe.FOV,
	"view_distance": Probe.REACH,
	"awareness_radius": Probe.BUBBLE,
	"see_over_coverage": Probe.SEE_OVER,
}
var _t: TestContext
var _pairs := 0
## The rids both cones leave out of every ray (a viewer's own body in the game).
var _exclude: Array = []
var _mismatches: Array[String] = []


func describe() -> Dictionary:
	return {
		"name": "The cone's savings draw today's cone, vertex for vertex",
		"description": "From a grid of eyes and facings in generated houses, and after a door "
			+ "swings, a piece is shoved and a piece leaves, the cone and the bubble are the "
			+ "reference algorithm's, within a tolerance of a thousandth of a pixel.",
		"tags": ["vision"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	# The session's own world is a far corner nobody looks at: the houses are built beside it.
	s.arena(Rect2(80_000, 80_000, 100, 100), { "walls": false })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	_t = t
	for entry in HOUSES:
		var setup := TestSetup.new()
		setup.house(entry[1], entry[0])
		setup.switch(&"nav.rebake", false)
		var world: Node2D = await Probe.build_world(t, setup)
		_compare_rooms(world, Cone.new(), Reference.new())
		await Probe.drop_world(t, world)
	var in_houses := _pairs
	t.check(
		in_houses >= MIN_HOUSE_PAIRS,
		"premise: %d rebuilds compared over the houses (%d needed)" % [in_houses, MIN_HOUSE_PAIRS],
	)
	await _compare_moving_pieces(t)
	await _compare_dents(t)
	var in_swing := _pairs - in_houses
	t.check(
		in_swing >= MIN_SWING_PAIRS,
		"premise: %d rebuilds compared over the moving pieces (%d needed)"
		% [in_swing, MIN_SWING_PAIRS],
	)
	t.check(
		_mismatches.is_empty(),
		"%d of %d cones differ from the reference: %s"
		% [_mismatches.size(), _pairs, "; ".join(_mismatches.slice(0, 4))],
	)


## Every room of `world`: a grid of eyes, each facing every way of `FACINGS`, rebuilt by `cone`
## (one persistent cone) and by `plain` (one reference).
func _compare_rooms(world: Node2D, cone: Cone, plain: Reference) -> void:
	for room: Dictionary in world.rooms:
		var rect: Rect2 = room["rect"]
		for i in GRID:
			for j in GRID:
				var at := rect.position + Vector2(
					lerpf(EDGE_MARGIN, rect.size.x - EDGE_MARGIN, float(i) / float(GRID - 1)),
					lerpf(EDGE_MARGIN, rect.size.y - EDGE_MARGIN, float(j) / float(GRID - 1)),
				)
				if Probe.solid_near(_t, at, SOLID_MARGIN):
					continue
				for degrees: float in FACINGS:
					_compare(cone, plain, at, Vector2.RIGHT.rotated(deg_to_rad(degrees)))


## The hand-laid rooms with a door that swings, a piece that is shoved and one that leaves.
func _compare_moving_pieces(t: TestContext) -> void:
	var setup := TestSetup.new()
	setup.layout(Probe.ROOMS, [Probe.DOOR])
	setup.switch(&"nav.rebake", false)
	var door_definition: Dictionary = WorldGen.object_definition("wardrobe").duplicate()
	door_definition["anchored"] = true
	setup.object(
		&"door",
		door_definition,
		HINGE + Vector2(0.0, DOOR_LENGTH * 0.5),
		{ "rotated": true },
	)
	setup.object(&"shoved", "wardrobe", SHOVE_AT, { "rotated": true })
	setup.object(&"walk_cover", "wardrobe", Vector2(600, 250), { "rotated": true })
	setup.object(&"table", "coffee_table", Probe.TABLE_AT)
	setup.actor(&"stander", &"puppet", STANDER_AT)
	var world: Node2D = await Probe.build_world(t, setup)
	var cone := Cone.new()
	var plain := Reference.new()
	var door: Node2D = world.objects[&"door"]
	var shoved: Node2D = world.objects[&"shoved"]
	# The game leaves the viewer's own body out of every ray: a piece left out here, as a viewer's
	# would be, by both cones (the table through the swing, the door through the shove).
	_exclude = [(world.objects[&"table"] as CollisionObject2D).get_rid()]
	var shapes: Array[PackedVector2Array] = []
	for step in SWING_STEPS + 1:
		var turn := float(step) / float(SWING_STEPS) * PI * 0.5
		door.global_rotation = turn
		door.global_position = HINGE + Vector2(0.0, DOOR_LENGTH * 0.5).rotated(turn)
		await t.frames(2)
		for k in SWING_EYES.size():
			_compare(
				cone,
				plain,
				SWING_EYES[k],
				Vector2.RIGHT.rotated(deg_to_rad(SWING_FACINGS[k])),
			)
		shapes.append(cone.cone.duplicate())
	t.check(
		_swing_changed(shapes),
		"premise: the swinging door changes what the last eye sees",
	)
	await _compare_shove(t, [door, shoved], cone, plain)
	await _compare_walk(t, world, cone, plain)
	await _compare_moving_body(t, world, cone, plain)
	await _compare_postures(t, world, cone, plain)
	await Probe.drop_world(t, world)


## Walls and pieces struck again and again: each hit dents the shape and, a frame later, replaces
## its collider with the convex pieces of the dented polygon, with no move of the body. One
## persistent cone and one reference rebuild the same grid of eyes after each volley.
func _compare_dents(t: TestContext) -> void:
	var setup := TestSetup.new()
	setup.layout(Probe.ROOMS, [Probe.DOOR])
	setup.switch(&"nav.rebake", false)
	setup.switch(&"physics.debris", false)
	setup.object(&"wardrobe", "wardrobe", Probe.WARDROBE_AT, { "rotated": true })
	setup.object(&"bookcase", "bookshelf", Vector2(300, 60))
	var world: Node2D = await Probe.build_world(t, setup)
	var targets := _dent_targets(world)
	var before := _pairs
	var shapes_before := Probe.collision_shapes(targets)
	await _dent_rounds(t, world, targets)
	t.check(
		Probe.collision_shapes(targets) > shapes_before,
		"premise: the dents cut the colliders into more shapes (%d, was %d)"
		% [Probe.collision_shapes(targets), shapes_before],
	)
	t.check(
		_pairs - before >= MIN_DENT_PAIRS,
		"premise: %d rebuilds compared over the dents (%d needed)"
		% [_pairs - before, MIN_DENT_PAIRS],
	)
	await Probe.drop_world(t, world)


## A piece shoved across the room and then freed (`pieces` = the door and the shoved piece), the
## door left out of every ray as a viewer's own body would be.
func _compare_shove(t: TestContext, pieces: Array, cone: Cone, plain: Reference) -> void:
	var door: Node2D = pieces[0]
	var shoved: Node2D = pieces[1]
	_exclude = [(door as CollisionObject2D).get_rid()]
	for step in SHOVE_STEPS:
		shoved.global_position = SHOVE_AT + SHOVE_STEP * float(step + 1)
		await t.frames(2)
		for at: Vector2 in SHOVE_EYES:
			_compare(cone, plain, at, Vector2.RIGHT.rotated(deg_to_rad(15.0)))
	_exclude = []
	shoved.queue_free()
	await t.frames(3)
	for at: Vector2 in SHOVE_EYES:
		_compare(cone, plain, at, Vector2.RIGHT.rotated(deg_to_rad(15.0)))


## The walls and the pieces of `world` that are struck.
func _dent_targets(world: Node2D) -> Array[Node2D]:
	var targets: Array[Node2D] = []
	for node in world.find_children("*", "StaticBody2D", true, false):
		if node.has_method("wall_segments"):
			targets.append(node)
	targets.append(world.objects[&"wardrobe"])
	targets.append(world.objects[&"bookcase"])
	return targets


## Compare the rooms, then after each volley on one of `targets`.
func _dent_rounds(t: TestContext, world: Node2D, targets: Array[Node2D]) -> void:
	var cone := Cone.new()
	var plain := Reference.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = Probe.HIT_SEED
	_compare_rooms(world, cone, plain)
	_compare_scattered(world, cone, plain, rng, Vector2.ZERO)
	for volley in Probe.VOLLEYS:
		# One piece or wall a volley, all hits within a few tens of px of one place: the dents
		# pile up there and the collider is cut into slivers.
		var target := targets[volley % targets.size()]
		var place := rng.randf()
		var struck := Vector2.ZERO
		for _k in HITS_PER_VOLLEY:
			struck = _strike(target, rng, place)
		await t.frames(3)
		_compare_rooms(world, cone, plain)
		_compare_scattered(world, cone, plain, rng, struck)


## `SCATTERED` eyes at random places of `world`'s rooms, each facing a random way; with `near` set,
## the places within `NEAR` px of it (the walls and pieces just struck).
func _compare_scattered(
	world: Node2D,
	cone: Cone,
	plain: Reference,
	rng: RandomNumberGenerator,
	near: Vector2,
) -> void:
	for _i in SCATTERED:
		var room: Dictionary = world.rooms[rng.randi() % world.rooms.size()]
		var rect: Rect2 = room["rect"]
		var at := rect.position + Vector2(rng.randf(), rng.randf()) * rect.size
		if near != Vector2.ZERO:
			at = near + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * NEAR
		if not Probe.solid_near(_t, at, SOLID_MARGIN):
			_compare(cone, plain, at, Vector2.from_angle(rng.randf() * TAU))


## One hit on `target` (a wall, or a piece) near `place` (0 to 1 along it); where it landed.
func _strike(target: Node2D, rng: RandomNumberGenerator, place: float) -> Vector2:
	var at: Vector2
	var normal: Vector2
	if target.has_method("wall_segments"):
		var segments: Array = target.wall_segments()
		var segment: PackedVector2Array = segments[int(place * float(segments.size() - 1))]
		var along: Vector2 = segment[1] - segment[0]
		var along_at := clampf(fposmod(place * 7.0, 1.0) + rng.randf_range(-0.05, 0.05), 0.0, 1.0)
		at = target.to_global(segment[0] + along * along_at)
		normal = along.orthogonal().normalized()
	else:
		var around := Vector2.from_angle(place * TAU + rng.randf_range(-0.4, 0.4))
		at = target.global_position + around * 12.0
		normal = around
	target.take_hit(Probe.hit(at, normal, rng.randf_range(10.0, 40.0)))
	return at


## A walking, turning eye passes a piece that moves and is then dented and re-cut. The reuse and
## memo counters must advance here, while every frame's polygons remain the plain rebuild's.
func _compare_walk(t: TestContext, world: Node2D, cone: Cone, plain: Reference) -> void:
	var cover: Node2D = world.objects[&"walk_cover"]
	var rng := RandomNumberGenerator.new()
	rng.seed = Probe.HIT_SEED + 91
	var shapes_before := Probe.collision_shapes([cover])
	var polygons_before := _savings_count(cone, &"polygon_reuses")
	var hits_before := _savings_count(cone, &"memo_hits")
	var validated_twice := 0
	var drawn: Array[PackedVector2Array] = []
	for step in 24:
		if step == 4 or step == 18:
			cover.global_position += Vector2(35, 20)
		if step == 10:
			for _hit in HITS_PER_VOLLEY:
				_strike(cover, rng, 0.4)
		await t.frames(3 if step == 10 else 2)
		var at := Vector2(140 + step * 40, 160 + 60 * sin(float(step) * 0.3))
		var validations := _savings_count(cone, &"validations")
		_compare(cone, plain, at, Vector2.from_angle(float(step) * 0.27))
		# A polygon is validated against its body once a rebuild: the memo holds each one.
		if _savings_count(cone, &"validations") - validations != _memoed(cone):
			validated_twice += 1
		drawn.append(cone.cone.duplicate())
	t.check(
		Probe.collision_shapes([cover]) > shapes_before,
		"premise: the walking sequence re-cut the blocker into more collision shapes",
	)
	t.check(_swing_changed(drawn), "premise: the walking, turning viewer's cone changes")
	t.check(
		_savings_count(cone, &"polygon_reuses") > polygons_before,
		"the walking sequence reuses static corner polygons across rebuilds",
	)
	t.check(
		_savings_count(cone, &"memo_hits") > hits_before,
		"the walking sequence asks for a polygon again within a rebuild and the memo answers",
	)
	t.check(
		validated_twice == 0,
		"%d of the walking sequence's rebuilds validated a polygon twice" % validated_twice,
	)


## A body that moves in every step of a walk, and again between two rebuilds with no physics step in
## between: the cone stays the reference's frame by frame (the polygon memo serves nothing across
## rebuilds).
func _compare_moving_body(t: TestContext, world: Node2D, cone: Cone, plain: Reference) -> void:
	var cover: Node2D = world.objects[&"walk_cover"]
	var hits_before := _savings_count(cone, &"memo_hits")
	var drawn: Array[PackedVector2Array] = []
	for step in MOVING_STEPS:
		cover.global_position += MOVING_STEP
		await t.frames(1)
		var at := Vector2(160 + step * 30, 200 + 50 * sin(float(step) * 0.4))
		var facing := Vector2.from_angle(float(step) * 0.2)
		_compare(cone, plain, at, facing)
		drawn.append(cone.cone.duplicate())
		# The body moves again before the physics server is told: both cones read the node's new
		# place for its polygon, the stale one for what a ray meets.
		cover.global_position -= MOVING_STEP * 0.5
		_compare(cone, plain, at, facing)
	t.check(_swing_changed(drawn), "premise: the cone changes as the body moves and the eye walks")
	t.check(
		_savings_count(cone, &"memo_hits") > hits_before,
		"the moving-body walk is read through the polygon memo",
	)


## One of the cone's fast-path counters, zero when it has no such counter.
func _savings_count(cone: Cone, key: StringName) -> int:
	var shapes: Variant = cone.get("_shapes")
	var count: Variant = shapes.get(key) if shapes != null else null
	return int(count) if count != null else 0


## How many polygons the cone's shapes hold in the memo of the rebuild just made, -1 when it has
## none.
func _memoed(cone: Cone) -> int:
	var shapes: Variant = cone.get("_shapes")
	if shapes == null or not shapes.has_method("memoed"):
		return -1
	return shapes.memoed()


## A character stands, crouches and stands again in the way of eyes that look over only what is
## lower than a standing body: its coverage changes with no move of its own.
func _compare_postures(t: TestContext, world: Node2D, cone: Cone, plain: Reference) -> void:
	var stander: Node2D = world.actors[&"stander"]
	var low := _sight.duplicate()
	low["see_over_coverage"] = Probe.LOOK_OVER_LOW
	var seen: Array[PackedVector2Array] = []
	for posture in [&"stand", &"crouch", &"stand", &"crouch"]:
		# A change of posture waits out its cooldown: ask until the body holds it.
		if not t.require(
			await t.until(func(): return stander.movement.set_posture(posture), 2.0),
			"the character takes the posture %s" % posture,
		):
			return
		await t.frames(2)
		for at: Vector2 in STANDER_EYES:
			_compare(cone, plain, at, Vector2.RIGHT, low)
		seen.append(cone.cone.duplicate())
	t.check(
		seen[0] != seen[1] and seen[1] != seen[2],
		"premise: the character's posture changes what the last eye sees",
	)


## Whether the cone polygon of the swing's last eye changed from the closed door to the open one.
func _swing_changed(shapes: Array[PackedVector2Array]) -> bool:
	return shapes.size() > 1 and shapes[0] != shapes[shapes.size() - 1]


## Rebuild `cone` and `plain` (the reference) from the same place and compare what they drew.
func _compare(
	cone: Cone,
	plain: Reference,
	at: Vector2,
	facing: Vector2,
	sight: Dictionary = _sight,
) -> void:
	var space := Probe.space(_t)
	cone.rebuild(space, at, facing, _exclude, sight)
	plain.rebuild(space, at, facing, _exclude, sight)
	_pairs += 1
	var reason := _difference(cone, plain)
	if reason != "":
		_mismatches.append("eye %s facing %s: %s" % [at, facing, reason])


## Why the two cones differ, or "" when they are the same within `Probe.TOLERANCE`.
func _difference(cone: Cone, plain: Reference) -> String:
	if cone.eye != plain.eye:
		return "eye"
	return Probe.polygons_differ(cone.cone, cone.bubble, plain.cone, plain.bubble)
