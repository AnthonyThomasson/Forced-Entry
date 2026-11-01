extends RefCounted
## The Vision domain's shared reads for the `tests/vision/` tests (`docs/player-vision.md`). Not a
## test. It reads the view only through what interface 24 publishes, and the numbers of the spec are
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
## The layout the cone tests share: a living room and a kitchen east of it, joined by a doorway
## (`DOOR`, 100 px wide) in the wall they share.
const ROOMS := [
	{ "key": "living", "type": "living_room", "rect": Rect2(0, 0, 700, 500) },
	{ "key": "kitchen", "type": "kitchen", "rect": Rect2(700, 0, 500, 500) },
]
const DOOR := { "pos": Vector2(700, 250), "width": 100.0 }
## The wardrobe (tall) and the coffee table (low) in the living room.
const WARDROBE_AT := Vector2(450, 130)
const TABLE_AT := Vector2(330, 300)


## Declare the two rooms, the wardrobe and the table, and a puppet `eye` to view by at `at`.
static func building(s: TestSetup, at: Vector2) -> void:
	s.layout(ROOMS, [DOOR])
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
