class_name DroppedItem extends Node2D
## Items domain: an item let go into the world: a dead character's weapon, or a thrown grenade's
## spoon. It falls from hand height in 3D (`SmallFlight`, in the twin space), bounces, then skids
## across the floor with a fading spin until it stops, glancing off walls and furniture and landing
## on top of a piece it falls onto (a table), as `DroppedItemConfig` tunes it. Shown by the 3D
## mirror (`LyingItemMesh`, from the item's `art.dropped_mesh()`). Nothing picks it up, and a
## dropped weapon is never despawned (a grenade's spoon is, grenade_spoon.gd).

## It moved, turned or changed height (once per physics frame while it is not at rest): the 3D
## mesh that shows it (`LyingItemMesh`) follows it.
signal shifted

## What it strikes in the twin space: walls, furniture, doors and vehicles; the characters it falls
## past (a spoon leaves a hand beside its thrower).
const MASK := PhysicsLayers.TWIN_SURFACES

## The item lying here (draws itself).
var item: Item
## Which way the item's art points (rad).
var _angle := 0.0
## Spin (rad/s).
var _spin := 0.0
## How it lies (`flip`: which side is up).
var _landing := {}
## Its fall: where it is, how high, how fast.
var _flight: SmallFlight
## How it leaves the hand: across the floor (px/s), until it is placed.
var _launch := Vector2.ZERO


func _ready() -> void:
	add_to_group(&"dropped_items")  # the 3D mirror shows each (`ItemMeshes`)
	ViewLayers.set_moving(self, true)


func _physics_process(delta: float) -> void:
	var event := _flight.step(TwinSpace.space_of(self), delta)
	global_position = _flight.at
	if _flight.rolling:
		_spin = move_toward(_spin, 0.0, DroppedItemConfig.spin_friction * delta)
	if event == SmallFlight.STRUCK:
		_spin *= -0.5
	_angle += _spin * delta
	shifted.emit()
	if _flight.resting:
		set_physics_process(false)  # At rest for good.
		ViewLayers.set_moving(self, false)


## Let `dropped` go pointing along `angle`, flying off at `velocity`; `place` puts it in the world.
static func spawn(dropped: Item, angle: float, velocity: Vector2) -> DroppedItem:
	var node := DroppedItem.new()
	node.name = "Dropped%s" % dropped.display_name
	node.item = dropped
	node._angle = angle
	node._launch = velocity
	node._spin = randf_range(6.0, 14.0) * (1.0 if randf() < 0.5 else -1.0)
	node._landing = { "flip": randf() < 0.5 }
	node._flight = SmallFlight.new(DroppedItemConfig.radius)
	node._flight.gravity = DroppedItemConfig.gravity
	node._flight.floor_restitution = DroppedItemConfig.bounce
	node._flight.wall_restitution = DroppedItemConfig.wall_bounce
	node._flight.friction = DroppedItemConfig.friction
	node._flight.mask = MASK
	return node


## How high the item is off the floor (px): its underside over the floor, or over the piece it
## lies on.
func altitude() -> float:
	return _flight.altitude()


## Which way the item's art points (rad), as it is drawn.
func heading() -> float:
	return _angle


## Which side faces up (`_landing.flip`): the side a loose gun lies on in 3D.
func flipped() -> bool:
	return _landing.get("flip", false)


## Put the item let go into `parent` at world point `at`. `held_from` is a clear point it was held
## from (the hand): if `at` lies inside a wall, the item starts where the way from there first meets
## it instead.
func place(parent: Node, at: Vector2, held_from: Vector2) -> void:
	parent.add_child(self)
	_flight.place(held_from, DroppedItemConfig.start_height)
	_flight.advance_to(TwinSpace.space_of(self), at)
	_flight.velocity = _launch
	global_position = _flight.at
