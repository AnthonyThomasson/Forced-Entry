extends RefCounted
## Tests: how the small items of a generated world settle (#194, D20,
## `docs/stacked-items.md`
## SI9). The world places them resting on their base, so none may topple or slide off at the
## start: after a short while each is asleep within a few px and a few degrees of where it was set.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const Probe := preload("res://tests/_objects/piece_probe.gd")
## What a settled item may have moved (px) and leaned (degrees), and how long it may take to sleep
## (sim s).
const MAX_MOVE := 3.0
const MAX_LEAN := 8.0
const SETTLE := 2.0


## The items under `root` (every piece in a room's `... Items` node) as `{ node, key, at }`, `at`
## the plan point under each one's centre of mass now.
static func items_of(root: Node) -> Array:
	var out: Array = []
	for piece in PlanProbe.pieces_under(root):
		if not String(piece.get_parent().name).ends_with(" Items"):
			continue
		if Probe.body(piece) == null:
			continue
		out.append({ "node": piece, "key": String(piece.name), "at": Probe.middle(piece) })
	return out


## Wait `SETTLE` s, then record a failed check for each item of `root` that is awake, moved over
## `MAX_MOVE` px or leans over `MAX_LEAN` degrees from where it was set; a premise that there are
## `min_items`. Returns the number of items checked.
static func check(t: TestContext, where: String, root: Node, min_items: int) -> int:
	await t.frames(2)
	var items := items_of(root)
	t.require(
		items.size() >= min_items,
		"%s: premise: %d items with a body" % [where, items.size()],
	)
	await t.seconds(SETTLE)
	var bad: Array[String] = []
	for item: Dictionary in items:
		var node: Node2D = item["node"]
		var moved := Probe.middle(node).distance_to(item["at"])
		var lean := Probe.lean(node)
		if not Probe.asleep(node) or moved > MAX_MOVE or lean > MAX_LEAN:
			bad.append("%s %s on %s: moved %.1f px, lean %.0f, %s" % [
				item["at"].snappedf(0.1),
				item["key"], node.get_parent().name, moved, lean,
				"asleep" if Probe.asleep(node) else "awake",
			])
	t.check(bad.is_empty(), "%s: every one of %d items settles in %.0f s: %s" % [
		where, items.size(), SETTLE, bad.slice(0, 6),
	])
	return items.size()
