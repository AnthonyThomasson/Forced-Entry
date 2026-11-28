class_name DecisionPrices
extends RefCounted
## AI DECISION sub-domain: what each piece of a snapshot build costs, in the work units of
## `DecisionBudget` (a unit is about half a millisecond of the piece's work on the measuring
## machine, `decision-prices.md`). A tuning holder (ADR 0003): statics only, set by tests with
## `set_static`.

const SnapshotBuild := preload("res://scenes/ai/perception/snapshot/snapshot_build.gd")

## The build's first piece (the claim: it gathers and freezes what the NPC knows).
static var cost_start: int = 1
## The first piece of an analysed hostile (its line of fire and the rings of fire spots, the rays
## of the fire search).
static var cost_hostile: int = 2
## The hostile's fire spots and ambush spot, from the rings (their routes and exposure).
static var cost_spots: int = 3
## One side of the hostile's flanks (a flank point, its route and its exposure).
static var cost_flanks: int = 1
## The rest of the hostile's analysis: its advance positions, option groups and sections.
static var cost_rest: int = 2
## The retreat spots (the heaviest of the finish's option groups: only with a threat to fall back
## from), worked out ahead of the finish.
static var cost_retreat: int = 3
## The build's finish (the shared facts, the other option groups, the demand and the sections).
static var cost_finish: int = 1
## A chunk of an ambush order's post ranking (`EntryPosts.AMBUSH_CHUNK` offsets, once a doorway and
## then kept).
static var cost_ambush: int = 1


## What a build piece of `kind` (`SnapshotBuild.Piece`) costs, or -1 for a kind with no price: every
## kind is priced explicitly, so a piece added without a price is found at once and not run as if
## it cost a start.
static func of_piece(kind: int) -> int:
	var priced := {
		SnapshotBuild.Piece.START: cost_start,
		SnapshotBuild.Piece.HOSTILE: cost_hostile,
		SnapshotBuild.Piece.SPOTS: cost_spots,
		SnapshotBuild.Piece.FLANKS: cost_flanks,
		SnapshotBuild.Piece.REST: cost_rest,
		SnapshotBuild.Piece.AMBUSH: cost_ambush,
		SnapshotBuild.Piece.RETREAT: cost_retreat,
		SnapshotBuild.Piece.FINISH: cost_finish,
	}
	return priced.get(kind, -1)
