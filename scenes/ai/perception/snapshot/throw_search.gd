extends RefCounted
## AI PERCEPTION sub-domain — a decision's search for a throw it could make (the `grenade_ready`
## fact, `docs/grenades.md` G17, G18) in steps: the state of it. `SnapshotThrows` holds the logic
## (`begin_search`, `search_ready`, `search_step`), as `AgentSnapshot` does for `SnapshotBuild`.
##
## The search goes through its `plan`, the sources a throw might be at (the shots' origin, each
## analysed hostile), each as the queries one throw of a kind carried asks: a lob clear from where
## the NPC stands, or a throw spot a short walk away (a `ThrowScan`). It stops at the first throw
## found. A step is a block of raw candidates, the rank pass or one route of the spot search in
## hand (`next_kind`), so a caller that prices them (the decision job's throw piece) spreads it
## over frames, and what a step does is the same at every block size: the answer is the one-shot
## search's. A search begun by a snapshot's demand writes its answer into the snapshot's facts as it
## ends.

## What the next step is (`ThrowScan.Kind`): a block of raw candidates, the rank pass, one route, or
## nothing (the search is over).
const Kind := preload("res://scenes/ai/perception/throw_scan.gd").Kind

## Whether a throw was found (once `over`).
var found := false
## Whether the search is over: a throw was found or every source is through.
var over := false
## The decision's context the search reads.
var ctx := {}
## The sources not yet tried, in order, and which one is next (`source`).
var plan: Array = []
var source := 0
## The queries of the source in hand, and which one is next (`at`).
var queries: Array = []
var at := 0
## The spot search in hand for the query at `at` (null: none), and the key its answer is kept by.
var scan: RefCounted
var key: Array = []
## The raw candidates a block step works through.
var block := 16
## The snapshot's demand, whose scratch each step takes (`open`) and whose facts take the answer
## (null: a search made by a plain caller).
var demand: RefCounted
var _throws: RefCounted
var _published := false


## Begin a search by `throws` (a `SnapshotThrows`) over `plan_`, `block_` raw candidates a block.
func begin(throws: RefCounted, ctx_: Dictionary, plan_: Array, block_: int) -> void:
	_throws = throws
	ctx = ctx_
	plan = plan_
	block = block_


## What the next step is (`Kind`): works through what needs no step first (a lob clear from where
## the NPC stands, a spot already worked out, the next source), a few rays at most.
func next_kind() -> int:
	var _scope: RefCounted = demand.open() if demand != null else null
	var kind: int = _throws.search_ready(self)
	if kind == Kind.DONE:
		_publish()
	return kind


## Whether the search is over.
func done() -> bool:
	return over


## Run the next step: at most one block of raw candidates, the rank pass or one route.
func step() -> void:
	var _scope: RefCounted = demand.open() if demand != null else null
	_throws.search_step(self)
	if over:
		_publish()


## The answer into the snapshot's facts, once.
func _publish() -> void:
	if demand != null and not _published:
		_published = true
		demand.facts["grenade_ready"] = found
