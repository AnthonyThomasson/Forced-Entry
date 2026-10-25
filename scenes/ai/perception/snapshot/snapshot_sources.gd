class_name SnapshotSources extends RefCounted
## The perception's modules the decision snapshot reads (`AgentSnapshot.setup`, and through it
## `SnapshotOptions.setup`): the event memory, the combat geometry, the doorway geometry, the
## doorway views, the grenade geometry, why a room is suspect and the entry claims heard. The
## perception fills it once in its `setup()`, after it has built them.

const AgentThrow = preload("res://scenes/ai/perception/agent_throw.gd")
const AgentSuspicion = preload("res://scenes/ai/perception/agent_suspicion.gd")

## The agent's event memory; see agent_memory.gd.
var memory: RefCounted
## The combat geometry; see agent_tactics.gd.
var tactics: RefCounted
## The doorway geometry; see agent_entry.gd.
var entry: RefCounted
## The doorway views and the walk round them; see agent_door_views.gd.
var views: RefCounted
## The grenade geometry (the lob, the danger zone, the escape); see agent_throw.gd.
var throw: AgentThrow
## Why a room is suspect; see agent_suspicion.gd.
var suspicion: AgentSuspicion
## The allies' entry claims heard on the radio; see stack/claim_ledger.gd.
var ledger: RefCounted
