class_name NavTick extends RefCounted

## The phases of the tick, in order.
enum Phase {
	FURNITURE,
	CHARACTERS,
	DUE,
	DONE,
}

## Navigation domain: one interval tick of a district's updater (`nav_updater.gd`) made in steps, a
## physics frame each, so no frame pays for the whole of it: the footprints of the furniture read a
## few pieces at a time (`NavPieces.Reader.step`: a scan and a cut count per frame, so the cold
## first tick, where every piece is cut, spreads too), then the characters' and the movement checks,
## then the due tiles (`NavDue`: the outlines binned by chunks, the tiles checked a few at a time).
## The work is the same as a tick made at once; only WHEN it is read moves: a later slice reads its
## pieces a frame later than the first, and the tick's answer (the baselines, the tiles due, the
## planning gather) is the updater's some frames after the timer fired (about nine for a steady
## tick of a district, 27 or more when every piece is cut: `tick.md`). A tick found still running
## when the timer fires again is skipped.

## Pieces scanned and cut a frame, outlines binned and tiles checked a frame (work counts, not
## times: the steps are the same on any machine).
const SCAN := 500
const CUTS := 32
const OUTLINES := 400
const TILES := 16

## What the tick found: the furniture's and the characters' footprints, whether either moved since
## the baselines it was given, and the tiles due (the whole of them only once `step` has returned
## true, and only when `moved`).
var furniture: Array = []
var characters: Array = []
var furniture_moved := false
var moved := false
var due: Array[Dictionary] = []
var _region: NavigationRegion3D
var _house: Node2D
var _site: NavSite
var _threshold := 0.0
var _baseline: Array
var _character_baseline: Array
var _pieces: NavPieces.Reader
var _scan: NavDue
var _phase := Phase.FURNITURE


## A tick of `region` over `house` (in the tree) against the baselines the updater holds
## (`baselines`: the furniture's, then the characters'): a footprint that moved more than
## `threshold` px is a move.
func _init(
	region: NavigationRegion3D,
	house: Node2D,
	site: NavSite,
	baselines: Array,
	threshold: float,
) -> void:
	_region = region
	_house = house
	_site = site
	_baseline = baselines[0]
	_character_baseline = baselines[1]
	_threshold = threshold
	_pieces = NavPieces.of(house).reader()


## Do this frame's step; true once the tick is made.
func step() -> bool:
	match _phase:
		Phase.FURNITURE:
			if _pieces.step(SCAN, CUTS):
				furniture = _pieces.walked()
				_phase = Phase.CHARACTERS
		Phase.CHARACTERS:
			characters = NavBuilder.character_holes(_house.get_parent())
			furniture_moved = moves(_baseline, furniture, _threshold)
			moved = furniture_moved or moves(_character_baseline, characters, _threshold)
			if not moved:
				_phase = Phase.DONE
			else:
				_scan = NavDue.new(
					_region, _site, furniture, characters,
					NavTiles.walking_at(_house.get_parent()),
				)
				_phase = Phase.DUE
		Phase.DUE:
			if _scan.step(OUTLINES, TILES):
				due = _scan.result()
				_phase = Phase.DONE
	return _phase == Phase.DONE


## Whether the footprints `b` differ from `a` enough to warrant a re-bake: a different piece
## count, or any footprint point shifted more than `threshold`. Both come from the same function,
## so points line up one-to-one when the piece count is unchanged.
static func moves(a: Array, b: Array, threshold: float) -> bool:
	if a.size() != b.size():
		return true
	for i in a.size():
		var pa: PackedVector2Array = a[i]
		var pb: PackedVector2Array = b[i]
		if pa.size() != pb.size():
			return true
		for j in pa.size():
			if pa[j].distance_to(pb[j]) > threshold:
				return true
	return false
