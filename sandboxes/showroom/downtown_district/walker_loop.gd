extends Node
## Walks the showroom's `walker` (a scripted character) back and forth between `points` while it is
## in the tree, so a set can show what happens when someone walks through it. When the set goes the
## walker is stood down: stopped, hidden and parked out of the way at `park`.

## The walker, the world points it walks between in turn and where it waits between sets.
var walker: Node2D
var points: Array[Vector2] = []
var park := Vector2.ZERO
var _puppet: Node
var _next := 0


func _ready() -> void:
	_puppet = TestContext.controller_of(walker)
	walker.global_position = points[0]
	walker.visible = true
	_next = 1


func _physics_process(_delta: float) -> void:
	if _puppet.has_arrived():
		_puppet.walk_to(points[_next])
		_next = (_next + 1) % points.size()


func _exit_tree() -> void:
	if is_instance_valid(walker) and is_instance_valid(_puppet):
		_puppet.stop()
		walker.visible = false
		walker.global_position = park
