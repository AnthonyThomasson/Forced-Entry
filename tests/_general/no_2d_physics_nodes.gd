extends RefCounted
## Shared by the no-2D-physics guard tests (#194, ADR 0014): the nodes of a built world
## that are a 2D physics node. There is none in the game any more: every sim root is a plain
## `Node2D` plan handle and the twin space is the only physics space.

## The classes no node of a world may be (a subclass counts: a `StaticBody2D` is a `PhysicsBody2D`).
const BANNED := [
	"PhysicsBody2D", "CollisionObject2D", "CollisionShape2D", "CollisionPolygon2D", "Area2D",
	"RayCast2D", "ShapeCast2D",
]


## Every node under `root` (root included) that is of a banned class, as `path (class)`.
static func offenders(root: Node) -> Array[String]:
	var found: Array[String] = []
	_walk(root, root, found)
	return found


## How many nodes lie under `root`, root included: what a test says it looked at.
static func count(root: Node) -> int:
	var total := 1
	for child in root.get_children():
		total += count(child)
	return total


static func _walk(root: Node, node: Node, found: Array[String]) -> void:
	for banned: String in BANNED:
		if node.is_class(banned):
			found.append("%s (%s)" % [root.get_path_to(node), node.get_class()])
			break
	for child in node.get_children():
		_walk(root, child, found)
