class_name GrenadeSpoon extends Item
## Items domain: a grenade's spoon (the safety lever), the tiny prop that pops off as it is thrown
## and lies on the floor. It is a `DroppedItem` carrying this item, so it falls, bounces and skids
## like one, drawn by its `art` part (`SpoonArt`); visual only, and the Despawner keeps their
## number in check. Never held.

## Speed (px/s) it is flung off at, to the side of the throw.
const TOSS := 90.0


func _init() -> void:
	super(null, null, SpoonArt.new())
	display_name = "Spoon"
	reach = 0.0


## Let a spoon go from `at` as a grenade is thrown along `throw_angle`: it spins off to one side
## into `parent`.
static func pop(at: Vector2, throw_angle: float, parent: Node) -> Node:
	var side := 1.0 if randf() < 0.5 else -1.0
	var velocity := (Vector2.from_angle(throw_angle + side * randf_range(1.0, 2.0)) * TOSS
			* randf_range(0.6, 1.0))
	var node := DroppedItem.spawn(GrenadeSpoon.new(), randf() * TAU, velocity)
	node.place(parent, at, at)
	Despawner.track(node)
	return node
