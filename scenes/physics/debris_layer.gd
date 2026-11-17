class_name DebrisLayer
extends "res://scenes/physics/mark_layer.gd"
## Physics System: the chips that have come to rest, kept as one layer under a world node instead
## of one node each. A chip (`debris.gd`) is a node only while it flies; as it lands it hands its
## place, turn, colour, size and shape here and frees itself, so a floor strewn with a thousand
## chips costs no node. The oldest are dropped past `Despawner.max_scene_objects`, the same bound
## the flying chips are tracked against, so the floor never accumulates chips without end. The 3D
## render shows the chips (`DebrisFx`, told by `PhysicsFxHook`); this is the record.

const NODE_NAME := "DebrisLayer"


## The debris layer held by `parent`, or null if none yet.
static func find(parent: Node) -> DebrisLayer:
	return parent.get_node_or_null(NODE_NAME) as DebrisLayer


## The debris layer under `parent` (the node the chips were spawned in), made on first use. Each
## parent has its own layer, freed with it.
static func layer(parent: Node) -> DebrisLayer:
	return _get_or_make(parent, NODE_NAME, DebrisLayer) as DebrisLayer


## Lay a chip to rest at world `at`, turned by `turn` (world radians): `size` px across, `shape`
## ("rect" | "tri" | "circle") in `color`.
func rest(at: Vector2, turn: float, color: Color, size: Vector2, shape: String) -> void:
	var chip := {
		"at": at,
		"turn": turn,
		"color": color,
		"size": size,
		"shape": shape,
	}
	_add(chip, Despawner.max_scene_objects)
