extends UnitSuite
## Native unit suite (pure logic): an NPC's AI frees itself once the NPC is freed. Its modules and
## their parts hold no reference back to a `RefCounted` that holds them, so no `RefCounted` cycle
## keeps any of it alive: the entry's leaves (`state`, `world`) and its ten parts (`claim`, ...,
## `radio`, each handed the entry at the call) and the combat's throw part hold no
## owner, the planner's parts and the controller's cadence are data that hold none, and the other
## parts of a node (the behaviour's, Locomotion's, the controller's, the perception's) hold it only
## as a node. Every preset, instanced, put in the tree (its controller builds the AI in `_ready`)
## and freed, leaves a `WeakRef` to each piece that reads null. Each NPC is made inside
## `_built_then_freed`, so no temporary of the calling test still holds a piece. The doorway
## geometry (`AgentEntry`) and its three parts (`posts`, `slots`, `layouts`, each handed it at the
## call) free themselves the same way, both bare (as `PlayerStack` builds one) and an NPC's.

const Entry := preload("res://scenes/ai/behavior/entry.gd")
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const NPCS := [
	"res://scenes/ai/npc.tscn",
	"res://scenes/ai/npc_defender.tscn",
	"res://scenes/ai/npc_invader.tscn",
]


## Instance the NPC at `path`, put it in the tree so its controller builds its AI, free it, and
## return what is left of each piece of that AI, by name.
func _built_then_freed(path: String) -> Dictionary:
	var npc: Node = (load(path) as PackedScene).instantiate()
	add_child(npc)
	var held := _held(npc.get_node("GoalController"))
	npc.free()
	return held


## Each piece of the AI under `controller` (the behaviour with its parts, its modules and theirs,
## the perception's parts, the planner's parts and the controller's own), by name, held by a
## `WeakRef`.
func _held(controller: Node) -> Dictionary:
	var behavior: Node = controller.get("_behavior")
	var entry: Entry = behavior.get("_entry")
	var combat: RefCounted = behavior.get("_combat")
	var loco: Node = behavior.get("_loco")
	var planner: Node = controller.get("_planner")
	var perception: Node = controller.get("_perception")
	var pieces := {
		"behavior": behavior, "behavior.task": behavior.get("task"),
		"behavior.watch": behavior.get("_watch"),
		"behavior.fight": behavior.get("fight"), "behavior.errand": behavior.get("errand"),
		"behavior.coverage": behavior.get("errand").coverage, "behavior.gait": behavior.get("gait"),
		"behavior.grenades": behavior.get("grenades"), "behavior.orders": behavior.get("orders"),
		"behavior.entries": behavior.get("entries"),
		"entry": entry, "entry.state": entry.state, "entry.world": entry.world,
		"entry.claim": entry.claim, "entry.approach": entry.approach,
		"entry.readiness": entry.readiness, "entry.orders": entry.orders,
		"entry.grenade": entry.grenade, "entry.listen": entry.listen, "entry.pie": entry.pie,
		"entry.sweep": entry.sweep, "entry.hold": entry.hold, "entry.radio": entry.radio,
		"combat": combat, "combat.throw": combat.get("throw"),
		"loco": loco, "loco.crowd": loco.get("crowd"), "loco.give_way": loco.get("give_way"),
		"loco.stall": loco.get("stall"), "loco.doors": loco.get("doors"),
		"planner": planner, "planner.walk": planner.get("_walk"),
		"planner.confines": planner.get("confines"),
		"controller.cadence": controller.get("_cadence"),
		"controller.comms": controller.get("_comms"),
		"controller.reflexes": controller.get("_reflexes"),
		"perception.sight": perception.get("sight"), "perception.house": perception.get("house"),
		"perception.hearing": perception.get("hearing"),
		"perception.orders": perception.get("orders"),
		"perception.contacts": perception.get("contacts"),
		"perception.grenades": perception.get("grenades"),
		"perception.entry": perception.get("entry"), "perception.views": perception.get("views"),
	}
	var held := {}
	for key: String in pieces:
		held[key] = weakref(pieces[key])
	return held


## The doorway geometry `entry` and each of its parts, by name, held by a `WeakRef`.
func _geometry_held(entry: AgentEntry) -> Dictionary:
	var pieces := {
		"geometry": entry, "geometry.posts": entry.posts, "geometry.slots": entry.slots,
		"geometry.layouts": entry.layouts,
	}
	var held := {}
	for key: String in pieces:
		held[key] = weakref(pieces[key])
	return held


## A bare doorway geometry, built as `PlayerStack` builds its own and handed to its parts at a call
## (no map: nothing is laid), dropped: what is left of each piece.
func _bare_geometry_dropped() -> Dictionary:
	var entry := AgentEntry.new()
	entry.set_house([], [])
	entry.geometry("door_0_0", "room", RID(), null)
	entry.posts.defend_spot(entry, "room", Vector2i(0, 1), RID(), null)
	return _geometry_held(entry)


## The doorway geometry of the NPC at `path` (its perception's), with the NPC freed: what is left
## of each piece.
func _npc_geometry_freed(path: String) -> Dictionary:
	var npc: Node = (load(path) as PackedScene).instantiate()
	add_child(npc)
	var perception: Object = npc.get_node("GoalController").get("_perception")
	var held := _geometry_held(perception.get("entry").doorways)
	npc.free()
	return held


## An entry whose world leaf holds it: the cycle the parts must never make.
func _entry_held_by_its_world() -> WeakRef:
	var entry := Entry.new()
	entry.world.set_meta(&"entry", entry)
	return weakref(entry)


func test_premise_a_leaf_holding_its_entry_keeps_it_alive() -> void:
	var held := _entry_held_by_its_world()
	assert_object(held.get_ref()).is_not_null()
	var entry: Entry = held.get_ref()
	entry.world.remove_meta(&"entry")  # Break the cycle: nothing leaks.


func test_a_doorway_geometry_and_its_parts_free_themselves() -> void:
	var cases := { "bare": _bare_geometry_dropped() }
	for path: String in NPCS:
		cases[path] = _npc_geometry_freed(path)
	for label: String in cases:
		var held: Dictionary = cases[label]
		assert_int(held.size()).is_equal(4)
		for key: String in held:
			var ref: WeakRef = held[key]
			assert_object(ref.get_ref()) \
				.override_failure_message("%s: %s is still alive" % [label, key]) \
				.is_null()


func test_every_npcs_ai_frees_itself_with_the_npc() -> void:
	for path: String in NPCS:
		var held := _built_then_freed(path)
		assert_int(held.size()).is_equal(44)
		for key: String in held:
			var ref: WeakRef = held[key]
			assert_object(ref).override_failure_message("%s: no %s" % [path, key]).is_not_null()
			if ref != null:
				assert_object(ref.get_ref()) \
					.override_failure_message("%s: %s is still alive" % [path, key]) \
					.is_null()
