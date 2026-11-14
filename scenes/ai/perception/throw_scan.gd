extends RefCounted
## AI PERCEPTION sub-domain — a throw-spot existence search in steps: whether a spot to throw a
## grenade from, within the short walk, exists for one aim (`ThrowSpots.scan_step` does the
## work of a step, this holds the search's state and what comes next, as `SnapshotBuild` does for
## the snapshot's author). The search is a fixed run of work: the raw candidates round the NPC and
## round the aim's spot, taken in blocks of a given count through the cheap tests (the navmesh snap,
## the room kept out of, the lob), then, when more than `ROUTES` passed, the rank pass over all of
## them, then the candidates that would be routed, one route per step, stopping at the first the
## walk reaches. A step never does more than one block, one rank pass or one route, so a caller that
## prices them spreads the search over frames; run to its end in one step each it is
## `grenade_ready`'s one-shot search. Nothing is timed or random: the answer is the same at every
## block size. It reads the physics space and the navmesh as each step runs.

## What the next step is: a block of raw candidates, the rank pass, one route, or nothing (done).
enum Kind {
	BLOCK,
	RANK,
	ROUTE,
	DONE,
}

## The most candidates routed.
const ROUTES := 10
## A block size past any search's raw candidates: the whole of them in one step.
const WHOLE := 1 << 30

## What the next step is.
var kind := Kind.BLOCK
## Whether a spot was found (once `done()`).
var found := false
## The candidate points the cheap tests passed (complete once `candidates_done`).
var points: Array = []
## Whether the blocks have all been through (`points` is complete).
var candidates_done := false
## The decision's context, the aim searched for and the bodies a ray ignores.
var ctx: Dictionary
var aim: ThrowAim
var exclude: Array
## The raw candidates (made by the first block step: `raw_made`), where the next block starts and
## which of them were tried (a snapped point is tested once).
var raw: Array = []
var raw_made := false
var cursor := 0
var tried := {}
## The candidates to route, in order, and which is next.
var routed: Array = []
var leg := 0
var _tactics: RefCounted


## A search for a throw spot for `aim_` by `tactics` (an `AgentTactics`). `known` are the candidate
## points already found for this aim (null: found here, block by block).
func _init(
	tactics: RefCounted, ctx_: Dictionary, aim_: ThrowAim, exclude_: Array, known: Variant = null,
) -> void:
	_tactics = tactics
	ctx = ctx_
	aim = aim_
	exclude = exclude_
	if known != null:
		points = known
		candidates_done = true
		blocks_done()


## Whether the search is over: `found` is its answer.
func done() -> bool:
	return kind == Kind.DONE


## Run the next step: at most `block` raw candidates, the rank pass, or one route.
func step(block: int) -> void:
	_tactics.throws.scan_step(_tactics, self, block)


## The blocks are through (`points` is complete): rank them when there are more than are routed,
## else route them as found.
func blocks_done() -> void:
	candidates_done = true
	if points.size() > ROUTES:
		kind = Kind.RANK
		return
	ranked(points.map(func(p): return { "point": p }))


## The candidates to route are in `routed_`, in order.
func ranked(routed_: Array) -> void:
	routed = routed_
	kind = Kind.ROUTE
	_end_if_none()


## The route of the candidate in hand: the search ends at the first the walk reaches (`reached`),
## or with the last.
func routed_one(reached: bool) -> void:
	if reached:
		found = true
		kind = Kind.DONE
		return
	leg += 1
	_end_if_none()


## Done, with no spot, when no candidate is left to route.
func _end_if_none() -> void:
	if leg >= routed.size():
		kind = Kind.DONE
