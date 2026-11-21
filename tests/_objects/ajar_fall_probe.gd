extends RefCounted
## Helper of the ajar-door fall tests (#194 flatdoor, `docs/doors.md` DR11): the gun range's four
## doorways onto the range fitted with a solid door each, ajar at the angle, hinge side and swing
## the test names, knocked down by a kick, and what each leaves of its doorway once it has settled.

const GunRange := preload("res://sandboxes/player_gun_range_sandbox.gd")
const Probe := preload("res://tests/_objects/piece_probe.gd")
## The free gap between a doorway's jambs (px: `DOORWAY` less the walls' 6 px ends each side).
const FREE_GAP := 48.0
## A kick's blow: the damage that fells a solid door and the shove it gives (px/s), at the lock.
const FELLING := 1000.0
const SHOVE := 800.0
## How far (px) from the leaf's middle a frag goes off, and how high.
const BLAST_AWAY := 40.0
const BLAST_HEIGHT := 42.0


## The range's layout with door `i` of `material` ajar `angles[i]` degrees, hinged on the side
## `hinges[i]` (-1 the west jamb, 1 the east) and swinging `intos[i]` (UP into its room, DOWN out
## onto the range).
static func doorways(
	angles: Array, hinges: Array, intos: Array, material := "solid"
) -> Array:
	var all: Array = GunRange._doorways()
	for i in angles.size():
		var spec: Dictionary = all[i]["door"]
		var middle: Vector2 = all[i]["pos"]
		spec["material"] = material
		spec["style"] = "panelled"
		spec["angle"] = angles[i]
		spec["hinge"] = middle + Vector2(GunRange.JAMB * float(hinges[i]), 0.0)
		spec["swing_into"] = intos[i]
	return all


## The door of range doorway `i`.
static func door(t: TestContext, i: int) -> Node2D:
	return t.object(StringName(GunRange.RANGE_DOORS[i]["name"]))


## Kick every one of the first `count` range doors down along `along` (UP: from the range, DOWN:
## from the room), let each settle, and check that it leaves its doorway clear.
static func fell_all(t: TestContext, angles: Array, along: Vector2, label: String) -> void:
	var count := angles.size()
	for i in count:
		var leaf = door(t, i)
		leaf.take_blow(&"kick", FELLING, along * SHOVE, 40.0)
	for i in count:
		var leaf = door(t, i)
		if not t.require(leaf.is_down(), "%s door %d is knocked down" % [label, i]):
			return
		await Probe.settle(t, leaf, 10.0)
		t.check(
			leaf.gap() >= FREE_GAP - 1.0,
			"%s door %d (ajar %.0f) leaves the doorway clear (%.0f of %.0f px; top %.0f, lean %.0f)"
				% [label, i, angles[i], leaf.gap(), FREE_GAP, Probe.top(leaf), Probe.lean(leaf)],
		)


## Blow up a frag a doorway's width short of each of the first `count` range doors, on the side
## `sides[i]` names (UP: the range's side of its wall, DOWN: the room's), at its middle's height,
## and check each leaf settles with its doorway clear.
static func blast_all(t: TestContext, angles: Array, sides: Array) -> void:
	for i in angles.size():
		var leaf = door(t, i)
		var row := GrenadeConfig.row(&"frag").duplicate()
		row["fragments"] = 0
		var from: Vector2 = leaf.global_position - (sides[i] as Vector2) * BLAST_AWAY
		Explosion.frag(from, t.world, null, row, BLAST_HEIGHT)
		await t.seconds(0.3)
		if not t.require(leaf.is_down(), "blasted door %d is knocked down" % i):
			return
		await Probe.settle(t, leaf, 10.0)
		t.check(
			leaf.gap() >= FREE_GAP - 1.0,
			(
				"blasted door %d (ajar %.0f, from %s) leaves the doorway clear "
				+ "(%.0f of %.0f px; top %.0f, lean %.0f)"
			) % [i, angles[i], sides[i], leaf.gap(), FREE_GAP, Probe.top(leaf), Probe.lean(leaf)],
		)
