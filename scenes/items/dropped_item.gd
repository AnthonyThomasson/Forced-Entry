class_name DroppedItem extends Node2D
## Items domain: an item let go into the world: a dead character's weapon, or a thrown grenade's
## spoon. It falls from hand height, bounces, then skids across the floor with a fading spin until
## it stops, glancing off walls and solid furniture (layer 1), as `DroppedItemConfig` tunes it.
## Drawn by the item's `art.draw_dropped()` over a shadow that closes in as it lands. Visual only:
## nothing picks it up, and a dropped weapon is never despawned (a grenade's spoon is,
## grenade_spoon.gd).

## Physics layers it glances off (walls + solid furniture).
const WALL_MASK := PhysicsLayers.SOLID

## The item lying here (draws itself).
var item: Item
## Across the floor (px/s).
var _velocity := Vector2.ZERO
## Above the floor (px).
var _height := 0.0
## Vertical speed (px/s, up).
var _rise := 0.0
## Which way the item's art points (rad).
var _angle := 0.0
## Spin (rad/s).
var _spin := 0.0
## How it lies, passed to draw_dropped (`flip`: which side is up).
var _landing := {}
## Reused wall sweep (a circle of `DroppedItemConfig.radius`).
var _query: PhysicsShapeQueryParameters2D


func _ready() -> void:
	z_index = DrawLayers.LYING  # Beneath the living and a vehicle's chassis, like a fallen body.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_height = DroppedItemConfig.start_height
	var circle := CircleShape2D.new()
	circle.radius = DroppedItemConfig.radius
	_query = PhysicsShapeQueryParameters2D.new()
	_query.shape = circle
	_query.collision_mask = WALL_MASK


func _physics_process(delta: float) -> void:
	_rise -= DroppedItemConfig.gravity * delta
	_height += _rise * delta
	var grounded := _height <= 0.0
	if grounded:
		_height = 0.0
		_rise = -_rise * DroppedItemConfig.bounce if _rise < -40.0 else 0.0
		_velocity = _velocity.move_toward(Vector2.ZERO, DroppedItemConfig.friction * delta)
		_spin = move_toward(_spin, 0.0, DroppedItemConfig.spin_friction * delta)
	_slide(_velocity * delta)
	_angle += _spin * delta
	queue_redraw()
	if grounded and _rise == 0.0 and _velocity.length_squared() < 1.0 and absf(_spin) < 0.05:
		set_physics_process(false)  # At rest for good.


func _draw() -> void:
	if item == null:
		return
	var away := PixelArt.away_from_light(self)
	item.art.draw_dropped(
		self,
		away * (0.5 + _height * DroppedItemConfig.shadow_per_height),
		_angle,
		Color(0.0, 0.0, 0.0, ArtCanvasConfig.drop_shadow_alpha),
		_landing,
	)
	item.art.draw_dropped(self, Vector2.ZERO, _angle, Color.WHITE, _landing)


## Let `dropped` go pointing along `angle`, flying off at `velocity`; `place` puts it in the world.
static func spawn(dropped: Item, angle: float, velocity: Vector2) -> DroppedItem:
	var node := DroppedItem.new()
	node.name = "Dropped%s" % dropped.display_name
	node.item = dropped
	node._angle = angle
	node._velocity = velocity
	node._spin = randf_range(6.0, 14.0) * (1.0 if randf() < 0.5 else -1.0)
	node._landing = { "flip": randf() < 0.5 }
	return node


## Put the item let go into `parent` at world point `at`. `held_from` is a clear point it was held
## from (the hand): if `at` lies inside a wall, the item starts where the way from there first meets
## it instead.
func place(parent: Node, at: Vector2, held_from: Vector2) -> void:
	parent.add_child(self)
	global_position = held_from
	_slide(at - held_from, false)


## Move by `motion`, stopping at a wall or solid furniture and (with `glance`) glancing off it.
func _slide(motion: Vector2, glance: bool = true) -> void:
	if motion.length_squared() < 0.000001:
		return
	var space := get_world_2d().direct_space_state
	_query.transform = Transform2D(0.0, global_position)
	_query.motion = motion
	var res := space.cast_motion(_query)
	if res[0] >= 1.0:
		global_position += motion
		return
	global_position += motion * res[0]
	if not glance:
		return
	_query.transform = Transform2D(0.0, global_position + motion * (res[1] - res[0]))
	_query.motion = Vector2.ZERO
	var info := space.get_rest_info(_query)
	var normal: Vector2 = info["normal"] if info.has("normal") else -motion.normalized()
	_velocity = _velocity.bounce(normal) * DroppedItemConfig.wall_bounce
	_spin *= -0.5
