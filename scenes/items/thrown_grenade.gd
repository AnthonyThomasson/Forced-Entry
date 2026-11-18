class_name ThrownGrenade
extends Node2D
## A grenade let go into the world (Items domain): it flies a real 3D flight in the twin space
## (`TwinSpace`, `ItemFlight`): thrown on the arc the shared planner chose (`GrenadeArc`, the lowest
## that clears what is in the way), it strikes what it meets (a wall, a lintel, furniture, a
## vehicle, a body), bounces off it and off the floor with the row's `restitution`, rolls and skids,
## can come to rest on top of a piece, and goes off when its fuse runs out. Docs: `docs/grenades.md`
## G3, G6 and G10. A world `Node2D` like `DroppedItem`; nobody picks it up or throws it back. While
## it lives it is in the group `live_grenades` (`kind`, `fuse_left()`, `throw_stats()`, `thrower`)
## for perception to query. On the fuse's end it calls the Projectile System's `Explosion.frag` /
## `Explosion.stun` with its `GrenadeConfig` row.

## It moved, turned or changed height (once per physics frame until it lies still): the 3D mesh
## that shows it (`LyingItemMesh`) follows it.
signal shifted

## A wall strike slower than this (px/s) is a nudge, not a clatter.
const MIN_CLATTER_SPEED := 30.0

## Which grenade this is (a `GrenadeConfig` id) and who threw it (may be gone by the time it goes
## off).
var kind: StringName = &""
## Who threw it; it may be gone by the time it goes off.
var thrower: Node
## The grenade item that draws it, in the thrown item's weapon style.
var item: Item
## The `GrenadeConfig` row it was thrown with.
var _row := {}
## Its flight: where it is, how high, how fast.
var _flight: ItemFlight
## Seconds left until it goes off (counted from the release).
var _fuse := 0.0
## Which way the art points (rad).
var _angle := 0.0
## Spin (rad/s).
var _spin := 0.0
## It has come to rest (the `rest` event was posted).
var _resting := false
## The thrower's body, passed for the first `GrenadeArc.THROWER_CLEAR` px of flight.
var _passed: Array[RID] = []
## How far (px) it has flown across the floor.
var _flown := 0.0


func _ready() -> void:
	add_to_group(&"live_grenades")
	ViewLayers.set_moving(self, true)


func _physics_process(delta: float) -> void:
	_fuse -= delta
	if _fuse <= 0.0:
		_detonate()
		return
	if _resting:
		return
	var before := _flight.at
	var pace := _flight.speed()
	var event := _flight.step(
		TwinSpace.space_of(self),
		delta,
		_passed if _flown < GrenadeArc.THROWER_CLEAR else GrenadeArc.NOBODY,
	)
	_flown += before.distance_to(_flight.at)
	global_position = _flight.at
	if _flight.rolling:
		_spin = move_toward(_spin, 0.0, GrenadeConfig.spin_friction * delta)
	_angle += _spin * delta
	match event:
		ItemFlight.LANDED:
			_post(&"bounce")
		ItemFlight.STRUCK:
			_spin *= -0.5
			if pace > MIN_CLATTER_SPEED:
				_post(&"bounce")
		ItemFlight.RESTED:
			_resting = true
			ViewLayers.set_moving(self, false)
			_spin = 0.0
			_post(&"rest")
	shifted.emit()


## Let a grenade go as `throw` says (of its `kind`, from `from` at `release` px up toward `to`,
## thrown by `thrower`, drawn in the weapon style `style` of the item it was thrown from,
## `ItemArt.style`) into `parent` (the world root): planned (`GrenadeArc.plan`, flown over the floor
## to rest and
## kept where it rests at the aim) and launched.
static func spawn(throw: GrenadeThrow, parent: Node) -> ThrownGrenade:
	var row := GrenadeConfig.row(throw.kind)
	var node := ThrownGrenade.new()
	node.name = "Thrown%s" % throw.kind.capitalize()
	node.kind = throw.kind
	node.thrower = throw.thrower
	node.item = ItemRegistry.create(int(row.get("slot", -1)), 1)
	node.item.art.style = throw.style
	node._row = row.duplicate()
	node._fuse = float(row.get("fuse", 3.0))
	node._passed = GrenadeArc.passed_by(throw.thrower)
	var course := GrenadeCourse.new()
	course.from = throw.from
	course.release = throw.release
	course.to = throw.to
	course.row = row
	course.space = TwinSpace.space_of(parent)
	course.passed = node._passed
	course.apex = throw.apex
	course.verify = true
	var launch := GrenadeArc.plan(course)
	node._flight = GrenadeArc.flight_for(row)
	node._flight.place(throw.from, throw.release)
	node._flight.velocity = launch.direction * launch.speed
	node._flight.rise = launch.rise
	node._angle = launch.direction.angle()
	node._spin = randf_range(8.0, 14.0) * (1.0 if randf() < 0.5 else -1.0)
	parent.add_child(node)
	node.global_position = throw.from
	return node


## How high it is off the floor (px): the underside's height over the floor, or over the piece it
## lies on (0 on the floor).
func altitude() -> float:
	return _flight.altitude()


## Which way its art points (rad), as it is drawn.
func heading() -> float:
	return _angle


## Seconds until it goes off.
func fuse_left() -> float:
	return maxf(_fuse, 0.0)


## What an onlooker may know of it: `{ kind, max_range, danger_radius, fuse, flash_cover_reach,
## max_blind }`, from the row it was thrown with (the same dictionary as
## `GrenadeItem.throw_stats()`).
func throw_stats() -> Dictionary:
	return GrenadeConfig.stats_of(kind, _row)


## Tell the world it hit the floor or a wall (`stage` &"bounce") or came to rest (&"rest"): the
## Audio domain voices the clatter, perception hears where it landed.
func _post(stage: StringName) -> void:
	EventBus.post(&"grenade", { "position": global_position, "kind": kind, "stage": stage })


## The fuse is out: the burst (Projectile System) and this node is done.
func _detonate() -> void:
	remove_from_group(&"live_grenades")
	var source: Node = thrower if is_instance_valid(thrower) else null
	var world := get_parent()
	match kind:
		&"frag": Explosion.frag(global_position, world, source, _row)
		&"stun": Explosion.stun(global_position, world, source, _row)
	queue_free()
