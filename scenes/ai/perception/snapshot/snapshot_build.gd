extends RefCounted
## AI PERCEPTION sub-domain — one decision snapshot being built in pieces. `AgentSnapshot` (the
## author) begins it (`begin_build`) and `step()` runs the next piece: START (gather the knowledge
## the build reads, set the decision up and work out the context), one HOSTILE piece per hostile
## given full analysis (with the cheap `line` entries of the listed hostiles ahead of it), then
## FINISH (the shared facts, the option groups, the demand set-up and the sections). Piece by piece
## it does exactly the work, in the order, that one `AgentSnapshot.build()` call does; `result()` is
## the dictionary `build()` returns. `next_piece()` says which kind runs next, for a caller that
## prices the pieces.
##
## This is a record of the build in progress: the author holds the logic, this holds the state, so
## the author keeps none between decisions. A build dropped half-way is simply freed (its
## walked-route token with it); nothing outside it has changed but the author's per-decision
## scratch, which the next build's START resets.

## The kinds of piece, in the order they run. DONE once the result is ready.
enum Piece {
	START,
	HOSTILE,
	FINISH,
	DONE,
}

## The author whose logic steps this build (an `AgentSnapshot`).
var author: RefCounted
## The house rooms, the goal and the activity line the snapshot is built for.
var rooms: Array
var goal: String
var activity: String
## Gathers the knowledge the build reads (the perception's); called once, by the START piece.
var gather: Callable
## Gives the entries the snapshot carries as they were at the start (optional); called once, by
## the START piece, and what it returned: `frozen`.
var freeze: Callable
var frozen := {}
## What `gather` returned: what the NPC knows at the start of the build.
var knowledge := {}
## The decision's context every group reads.
var ctx := {}
## What the hostile pieces fill in: `per_target`, `per_sections`, `analyses`, `targets`; the
## FINISH piece adds what the whole decision shares.
var parts := {}
## The ids of the hostiles given full analysis (a piece runs for each, until `parts.targets` holds
## them all), and where in the contacts' order the next piece goes on.
var analysed: Array = []
var cursor := 0
## The kind of piece that runs next.
var piece := Piece.START
## The doorway views' walked-route memo, open from START to FINISH (`begin_decision`).
var token: RefCounted
var _result := {}


## The kind of piece `step()` runs next (`Piece.DONE` once the build is complete).
func next_piece() -> int:
	return piece


## Whether every piece has run: `result()` is ready.
func done() -> bool:
	return piece == Piece.DONE


## Run the next piece (nothing once done).
func step() -> void:
	if piece != Piece.DONE:
		author.advance_build(self)


## The finished snapshot (only once `done()`).
func result() -> Dictionary:
	assert(done(), "SnapshotBuild.result() before the build is done")
	return _result


## Hand over the finished snapshot and close the build. Called by the author's FINISH piece.
func finish(snapshot: Dictionary) -> void:
	_result = snapshot
	token = null
	piece = Piece.DONE
