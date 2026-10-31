class_name DoorFactory
## Objects-domain factory: turns a door DEFINITION (a plain data dict from World-Gen's catalogue,
## `DoorCatalog`) and the doorway it stands in into a runtime `Door` node (architecture interface
## 2). Objects owns the field schema; World-Gen owns which doors exist.
##
## Definition fields: `name`, `material` (`DoorMaterialConfig.materials`' key: hollow, solid, steel,
## glass), `style` (what the door painter draws: flush, panelled, plank, riveted, peephole, panes)
## and `color` (the leaf's base colour).
## `opening` fields: `pos` (the doorway's centre, world), `hinge` (the world point on the jamb the
## leaf turns about, where a wall's end stands on one side of the gap: a wall's collider reaches
## half its thickness into the gap, so that is the doorway's free width, which the leaf fills),
## `swing_into` (the unit vector into the room it swings into) and, optionally, `name` (the node's
## name, default the definition's) and `angle` (degrees from shut it starts at, default 0).


## Build the door of `definition` in the doorway `opening` and add it under `parent`. Returns it.
static func spawn(opening: Dictionary, definition: Dictionary, parent: Node) -> Door:
	if definition.is_empty():
		push_error("DoorFactory: empty definition")
		return null
	var door := Door.new()
	door.name = String(opening.get("name", definition.get("name", "Door")))
	door.setup(opening, definition)
	door.place(parent)
	parent.add_child(door, true)
	return door
