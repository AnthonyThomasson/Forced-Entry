class_name NpcTuning extends Node
## An NPC's tunables, the AI's one authoring surface: the controller's `Tuning` child
## (`GoalController.tuning`), holding one topic node per concern, each only exports. Per NPC:
## `npc.tscn` authors the hub and its fifteen topics as its children, a preset overrides a topic's
## values on its scene (`Tuning/Hostility.on_trespass`), and a test or switch sets one NPC's value
## as an indexed path on its controller (`tuning:entry:ready_timeout`). The scene hands the hub its
## topics as node references, resolved as the NPC is instantiated, so they are there before it joins
## the tree.

## How it decides (the planner's config, the decide cadence, commitment).
@export var decision: NpcDecisionTuning
## How what it knows is worded for Von.
@export var context: NpcContextTuning
## The combat geometry (cover, flanks, firing spots).
@export var tactics: NpcTacticsTuning
## How it fights.
@export var combat: NpcCombatTuning
## How it searches a room by sight.
@export var coverage: NpcCoverageTuning
## What it remembers.
@export var memory: NpcMemoryTuning
## What it sees and hears.
@export var senses: NpcSensesTuning
## The team radio.
@export var radio: NpcRadioTuning
## Tactical entry: whether, and its timing and team.
@export var entry: NpcEntryTuning
## The doorway geometry of a tactical entry.
@export var entry_geometry: NpcEntryGeometryTuning
## The entry guard and the doorway views.
@export var entry_guard: NpcEntryGuardTuning
## Grenades: the evade reflex, throw spots, blind fire.
@export var grenades: NpcGrenadesTuning
## Where it looks.
@export var watch: NpcWatchTuning
## Whom it takes for hostile.
@export var hostility: NpcHostilityTuning
## How it moves.
@export var pace: NpcPaceTuning


## A hub with its fifteen topics at their defaults, built in code (each topic its child, so freeing
## the hub frees them): for a unit test that builds a module alone, with no NPC scene.
static func defaults() -> NpcTuning:
	var hub := NpcTuning.new()
	hub.name = "Tuning"
	hub.decision = _topic(hub, NpcDecisionTuning.new(), "Decision")
	hub.context = _topic(hub, NpcContextTuning.new(), "Context")
	hub.tactics = _topic(hub, NpcTacticsTuning.new(), "Tactics")
	hub.combat = _topic(hub, NpcCombatTuning.new(), "Combat")
	hub.coverage = _topic(hub, NpcCoverageTuning.new(), "Coverage")
	hub.memory = _topic(hub, NpcMemoryTuning.new(), "Memory")
	hub.senses = _topic(hub, NpcSensesTuning.new(), "Senses")
	hub.radio = _topic(hub, NpcRadioTuning.new(), "Radio")
	hub.entry = _topic(hub, NpcEntryTuning.new(), "Entry")
	hub.entry_geometry = _topic(hub, NpcEntryGeometryTuning.new(), "EntryGeometry")
	hub.entry_guard = _topic(hub, NpcEntryGuardTuning.new(), "EntryGuard")
	hub.grenades = _topic(hub, NpcGrenadesTuning.new(), "Grenades")
	hub.watch = _topic(hub, NpcWatchTuning.new(), "Watch")
	hub.hostility = _topic(hub, NpcHostilityTuning.new(), "Hostility")
	hub.pace = _topic(hub, NpcPaceTuning.new(), "Pace")
	return hub


## `topic`, named `node_name` and added under `hub`.
static func _topic(hub: Node, topic: Node, node_name: String) -> Node:
	topic.name = node_name
	hub.add_child(topic)
	return topic
