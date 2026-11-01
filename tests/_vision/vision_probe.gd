extends RefCounted
## The Vision domain's shared reads for the `tests/vision/` tests (`docs/player-vision.md`). Not a
## test. It reads the view only through what interface 25 publishes, and the numbers of the spec are
## kept here as consts, so a test checks the spec and not the code.
##
## What the tests read:
## - `PlayerView` (class_name, `scenes/vision/`), the view built for one character, a node in the
##   group `player_view` under the world root, with
##   - `cone() -> PackedVector2Array`: the cone polygon, the eye first and then one corner per ray
##     from the left edge to the right (empty while the viewer has no facing);
##   - `bubble() -> PackedVector2Array`: the near bubble's polygon round the eye, the line of sight
##     bounding it;
##   - `sees(point) -> bool`: the point is in the cone or the bubble;
##   - `viewer() -> Node2D`: the character the view was built for;
##   - `static watch(root, viewer) -> PlayerView`: build it for `viewer` (null while
##     `VisionConfig.enabled` is off).
## - `VisionConfig.enabled` (class_name static holder): the switch.
## - The viewer is any character: `global_position`, `facing`, `get_rid()`.
## - The world is plain Godot physics: the solid layer (`PhysicsLayers.SOLID`, bit 1) and each
##   piece's `get_surface().coverage`.

const GROUP := &"player_view"
const WorldScript := preload("res://scenes/testing/test_world.gd")
## The visibility bits of the spec (V5): what stays where it is, what moves, the overlays.
const WORLD := 1
const MOVING := 2
const OVERLAY := 4
## The spec's sight (V1), kept here on its own: the cone's width (degrees) and reach (px), the
## bubble's radius (px) and the height (coverage) a line of sight looks over.
const FOV := 110.0
const REACH := 2520.0
const BUBBLE := 48.0
const SEE_OVER := 60.0
## How far (px) a vertex of a cone may sit from the reference cone's: the reach is 2520 px, so this
## is 4e-7 of it.
const TOLERANCE := 0.001
## The dents the cone tests deal: this many volleys, from this random seed, and a sight that looks
## over only what is lower than `LOOK_OVER_LOW` (a standing body, 60, blocks it; a crouched one, 35,
## does not).
const VOLLEYS := 8
const HIT_SEED := 31
const LOOK_OVER_LOW := 50.0
## The layout the cone tests share: a living room and a kitchen east of it, joined by a doorway
## (`DOOR`, 100 px wide) in the wall they share.
const ROOMS := [
	{ "key": "living", "type": "living_room", "rect": Rect2(0, 0, 700, 500) },
	{ "key": "kitchen", "type": "kitchen", "rect": Rect2(700, 0, 500, 500) },
]
const DOOR := { "pos": Vector2(700, 250), "width": 100.0 }
## A doorway with a door in it (`doorway`): 52 px free between jambs 40 px apart whose ends the
## walls reach 6 px into; the hinge sits 20 px from the doorway's middle.
const DOOR_WIDTH := 52.0
const JAMB := 20.0
## The wardrobe (tall) and the coffee table (low) in the living room.
const WARDROBE_AT := Vector2(450, 130)
const TABLE_AT := Vector2(330, 300)


## The rooms of `ROOMS` moved by `offset`, for a world built far from the session's own.
static func rooms_at(offset: Vector2) -> Array:
	var moved := []
	for room: Dictionary in ROOMS:
		var rect: Rect2 = room["rect"]
		var shifted := room.duplicate()
		shifted["rect"] = Rect2(rect.position + offset, rect.size)
		moved.append(shifted)
	return moved


## A doorway in the wall the rooms share (x 700), centred at `y`, holding a door named `id` of
## `material` and `style` that hangs on the north jamb and swings into the kitchen; moved by
## `offset` with `rooms_at`.
static func doorway(
	y: float,
	material: String,
	style: String,
	id: String,
	offset := Vector2.ZERO,
) -> Dictionary:
	return {
		"pos": Vector2(700, y) + offset, "width": DOOR_WIDTH,
		"door": {
			"name": id, "material": material, "style": style,
			"hinge": Vector2(700, y - JAMB) + offset, "swing_into": Vector2.RIGHT,
		},
	}


## Declare the two rooms joined by `doorways` (the open `DOOR` unless given), the wardrobe and the
## table, and a puppet `eye` to view by at `at`.
static func building(s: TestSetup, at: Vector2, doorways: Array = [DOOR]) -> void:
	s.layout(ROOMS, doorways)
	s.switch(&"nav.rebake", false)
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT)
	s.object(&"table", "coffee_table", TABLE_AT)
	s.actor(&"eye", &"puppet", at)


## The view of the test world (null without one).
static func view(t: TestContext) -> PlayerView:
	var found := views(t)
	return null if found.is_empty() else found[0]


## Every view under the test world.
static func views(t: TestContext) -> Array[PlayerView]:
	return views_under(t.world)


## Every view under `root`, a world of the test's own.
static func views_under(root: Node) -> Array[PlayerView]:
	var found: Array[PlayerView] = []
	for n in root.get_tree().get_nodes_in_group(GROUP):
		if root.is_ancestor_of(n):
			found.append(n as PlayerView)
	return found


## A world of the test's own, built from `setup` beside the session's (the test builds worlds one
## after the other, and frees each with `drop_world`).
static func build_world(t: TestContext, setup: TestSetup) -> Node2D:
	var world: Node2D = WorldScript.new()
	world.name = "Twin"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	t.world.get_parent().add_child(world)
	await world.build(setup)
	return world


## Free a world made by `build_world` and give back what its setup changed.
static func drop_world(t: TestContext, world: Node2D) -> void:
	world.restore()
	world.queue_free()
	await t.frames(2)


## Put `who` at `at` facing along `dir` and wait until its facing (derived from its aim a frame
## later) and the view have caught up. False when its facing never comes round.
static func place(t: TestContext, who: Node2D, at: Vector2, dir: Vector2) -> bool:
	who.global_position = at
	t.puppet(&"eye").aim_at(at + dir * 100.0)
	for _i in 3:
		await t.frames(1)
	return (who.get("facing") as Vector2).distance_to(dir.normalized()) < 0.01


## The physics space of the test world.
static func space(t: TestContext) -> PhysicsDirectSpaceState2D:
	return t.world.get_world_2d().direct_space_state


## The first thing on the line `from` to `to` too tall to see over (the spec's V1 line of sight), or
## {}; `exclude` the rids left out.
static func blocker(
	t: TestContext,
	from: Vector2,
	to: Vector2,
	exclude: Array,
) -> Dictionary:
	return SightRay.hit(space(t), from, to, exclude, SEE_OVER)


## Whether `point` is in the sight of an eye at `from` facing `facing` by the spec's V1: within the
## reach, in the bubble or the cone, and with no tall blocker on the line.
static func in_sight(
	t: TestContext,
	from: Vector2,
	facing: Vector2,
	point: Vector2,
	exclude: Array,
) -> bool:
	var to := point - from
	if to.length() > REACH:
		return false
	var in_cone := absf(facing.angle_to(to)) <= deg_to_rad(FOV) * 0.5
	if not in_cone and to.length() > BUBBLE:
		return false
	return blocker(t, from, point, exclude).is_empty()


## Whether something solid lies within `margin` px of `point` (a sample on a wall's edge is neither
## clearly seen nor clearly hidden, so a test leaves it out).
static func solid_near(t: TestContext, point: Vector2, margin: float) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = margin
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, point)
	query.collision_mask = PhysicsLayers.SOLID
	return not space(t).intersect_shape(query, 1).is_empty()


## Whether the view's capture draws `node`: it and every canvas item above it share a bit with the
## capture's cull mask (`CanvasItem.visibility_layer`, `Viewport.canvas_cull_mask`).
static func in_capture(of_view: PlayerView, node: Node) -> bool:
	var mask := of_view.capture().canvas_cull_mask
	var at := node
	while at != null:
		if at is CanvasItem and ((at as CanvasItem).visibility_layer & mask) == 0:
			return false
		at = at.get_parent()
	return true


## Whether the view's capture lights the world by `light` (a Light2D): the engine gathers a
## viewport's lights from its canvases alone and never by `visibility_layer`, so a light is in the
## capture when it is on the capture's world canvas or a canvas layer under the capture.
static func light_in_capture(of_view: PlayerView, light: CanvasItem) -> bool:
	var capture := of_view.capture()
	var canvas := light.get_canvas()
	if canvas == capture.find_world_2d().canvas:
		return true
	for layer in capture.find_children("*", "CanvasLayer", true, false):
		if (layer as CanvasLayer).get_canvas() == canvas:
			return true
	return false


## How many collision shapes `targets` hold between them.
static func collision_shapes(targets: Array[Node2D]) -> int:
	var count := 0
	for target in targets:
		count += target.find_children("*", "CollisionShape2D", false, false).size()
	return count


## A hit of `damage` at `at` on a surface facing `normal`, flying straight in.
static func hit(at: Vector2, normal: Vector2, damage: float) -> HitInfo:
	var info := HitInfo.new()
	info.position = at
	info.normal = normal
	info.direction = -normal
	info.damage = damage
	info.speed_factor = 1.0
	return info


## Why a cone and bubble (`got_cone`, `got_bubble`) differ from the polygons `want_cone` and
## `want_bubble` by more than `TOLERANCE` at any vertex, or "" when they are the same.
static func polygons_differ(
	got_cone: PackedVector2Array,
	got_bubble: PackedVector2Array,
	want_cone: PackedVector2Array,
	want_bubble: PackedVector2Array,
) -> String:
	for which in ["cone", "bubble"]:
		var got: PackedVector2Array = got_cone if which == "cone" else got_bubble
		var want: PackedVector2Array = want_cone if which == "cone" else want_bubble
		if got.size() != want.size():
			return "%s has %d vertices, not %d" % [which, got.size(), want.size()]
		for i in got.size():
			if got[i].distance_to(want[i]) > TOLERANCE:
				return "%s vertex %d is %s, not %s" % [which, i, got[i], want[i]]
	return ""


## Wait until the test camera holds still (the canvas transform's origin within half a pixel for
## five drawn frames in a row), and return whether it did within 5 s. The camera starts where the
## last test left it and eases in, one step a drawn frame, so what the test reads of the screen
## (is a body on it, is it drawn) is only true once it has arrived. Only a drawn frame counts: a
## window's first frames run several physics frames each, and the view would look still before the
## camera had moved at all.
static func view_still(t: TestContext) -> bool:
	# The origin at the last drawn frame, that frame's number, and the drawn frames it held still.
	var last: Array = [Vector2.INF, -1, 0]
	return await t.until(
		func() -> bool:
			var frame := Engine.get_process_frames()
			if frame == last[1]:
				return false
			var origin := t.world.get_viewport().get_canvas_transform().origin
			last[2] = last[2] + 1 if origin.distance_to(last[0]) < 0.5 else 0
			last[0] = origin
			last[1] = frame
			return last[2] >= 5,
		5.0,
	)
