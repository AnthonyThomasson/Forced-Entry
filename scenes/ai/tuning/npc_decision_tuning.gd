class_name NpcDecisionTuning extends Node
## How an NPC decides: the pursuit and territory primitives, the Von endpoint it asks, the decide
## cadence and commitment, and the decision tree's config. One topic node of the NPC's tunables,
## under its controller's `Tuning` hub (`NpcTuning.decision`), per NPC: its scene authors it (the
## presets' overrides), a test sets it as an indexed path (`tuning:decision:<name>`). Only exports,
## and the local Von server's constants: the defaults of `server_url` and `model`, which the dev
## launcher (`decision_server_launcher.gd`) starts and probes the server with too.

## The host the local Von server listens on.
const SERVER_HOST := "127.0.0.1"
## The port the local Von server listens on.
const SERVER_PORT := 8000
## The decision endpoint's path.
const SERVER_PATH := "/v1/systemone"
## The Von model the NPCs name by default (`model`).
const MODEL := "von-1.2.0"

## Pursuit primitive: when true this NPC actively hunts hostiles instead of doing chores. Once a
## hostile is known every decision starts at COMBAT, and IDLE (chores) is never offered — a passive
## interaction freezes the NPC's facing and blinds it. Turn off for an NPC whose goal is unrelated
## to fighting.
@export var pursue_hostiles: bool = true
## Territory primitive: when true the NPC fights from inside the house — combat options outside it
## are never offered, and it won't chase a contact out of the house.
@export var defend_territory: bool = false
## The `/v1/systemone` endpoint to ask.
@export var server_url: String = "http://%s:%d%s" % [SERVER_HOST, SERVER_PORT, SERVER_PATH]
## Model name sent with each request.
@export var model: String = MODEL
## Minimum seconds between decisions while holding (the re-decide cadence once free to change).
@export var decide_interval: float = 1.0
## Seconds a fight runs before Von re-chooses its tactic (it re-chooses sooner if the fight lapses).
@export var tactic_interval: float = 3.0
## Safety cap (s) on committing to a move or to reaching an object, so a blocked path still
## re-decides.
@export var max_commit_time: float = 6.0
## Seconds to stay in a chosen interaction before ending it and re-deciding (covers Von's
## statelessness so multi-step goals advance).
@export var interaction_dwell: float = 3.0
## Decision-tree nodes never offered to this NPC (see scenes/ai/decision/decision_tree.gd), e.g.
## [&"advance"] for one that never closes in. `pursue_hostiles` adds &"idle".
@export var disabled_nodes: Array[StringName] = []
## Per-node overrides merged over the tree's defaults: { node_id: { field: value } } — e.g. a
## different `question` for &"flank".
@export var node_overrides: Dictionary = {}
## Ordered fact → node: a decision starts at the first rule's node whose fact holds, skipping the
## broader levels above it (e.g. under fire → straight to COMBAT). `pursue_hostiles` adds
## hostile_known → combat. Facts: see the perception snapshot.
@export var entry_rules: Dictionary = { &"under_fire": &"combat", &"engaged": &"combat" }
## Take a level's only option without asking Von (saves a round-trip per auto-picked level).
@export var skip_single_option: bool = true
## Most options offered at one level (positions, rooms, leads); interactions are not capped.
@export var max_options_per_level: int = 4
