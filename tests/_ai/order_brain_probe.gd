extends RefCounted
## Shared helpers for the leadership tests (not a test itself):
## `const OrderBrain := preload("res://tests/_ai/order_brain_probe.gd")`. An NPC's brain read under
## an order (`docs/leadership.md` LD5, LD6): its controller (`brain`), the fact `ordered` of its
## last decision, its decision walks and their levels, the running leaf's `primitive` and `params`,
## the ORDER node (`on_order`), and where its entry has it stand in an ordered stack (`stack_point`,
## `stacked`). The NPC is read only through its controller's public reads (`current_act()`,
## `debug_state()`, `debug_entry()`). The squad, its orders and their radio are `order_probe.gd`'s
## (`Order`).


# --- The NPC --------------------------------------------------------------------------------------


## The controller of actor `id`.
static func brain(t: TestContext, id: StringName) -> Node:
	return t.controller(id, &"debug_state")


## Whether the NPC's last decision snapshot had the fact `ordered` (LD5).
static func ordered(b: Node) -> bool:
	return (bool((b.debug_state().get("facts", {}) as Dictionary).get("ordered", false))
			if b != null
			else false)


## How many decision walks the NPC has started.
static func decisions(b: Node) -> int:
	return int(b.debug_state().get("decisions", 0)) if b != null else 0


## The running leaf's primitive (`debug_state()["primitive"]`).
static func primitive(b: Node) -> String:
	return String(b.debug_state().get("primitive", "")) if b != null else ""


## The running leaf's params (`debug_state()["params"]`).
static func params(b: Node) -> Dictionary:
	return b.debug_state().get("params", {}) if b != null else {}


## Whether the NPC is carrying out an order: its decision path starts at the ORDER node (LD6).
static func on_order(b: Node) -> bool:
	return b != null and String(b.current_act()).begins_with("order")


## The levels of the NPC's last decision walk.
static func levels(b: Node) -> Array:
	return b.debug_state().get("decision", {}).get("levels", []) if b != null else []


# --- The NPC in an ordered stack (LD9) ------------------------------------------------------------


## Where actor `id`'s running entry has it stand in the stack (`debug_entry()["stack_point"]`), or
## INF.
static func stack_point(t: TestContext, id: StringName) -> Vector2:
	var e: Dictionary = brain(t, id).debug_entry()
	var p = e.get("stack_point", Vector2.INF)
	return p if p is Vector2 else Vector2.INF


## Whether actor `id` is in its stack slot (its entry's phase is past the approach: `stack` or
## later).
static func stacked(t: TestContext, id: StringName) -> bool:
	var phase := String(brain(t, id).debug_entry().get("phase", ""))
	return phase != "" and phase != "approach"
