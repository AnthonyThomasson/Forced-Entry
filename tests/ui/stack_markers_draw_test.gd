extends GameTest
## Desired (ticket #41): the stack markers put the human's place in the stack on the floor. Each
## slot beside the doorway is drawn with its number, slots held by the AI dimmer than the human's
## own, which is highlighted; nothing is drawn while the stack has no reservation. The node only
## observes `view()` of the human's stack.
##
## Extended (LD18): in a played match every stack of the human's side, ordered or its own, shows its
## numbered rings, read from the squad's view (`Squad.view()["stacks"]`:
## `{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }`), as well
## as the human's own `PlayerStack.view()`: in claim order, dim while the member is on its way
## (`held`, not `there`), filled once there, the human's own bright (`mine`), free slots faint; both
## sides of a split stack and second rows; from the first claim until the stack is through (it
## leaves the squad's view). The markers watch the squad through `watch_squad(view: Callable)`, and
## `drawn()` gives each ring as `{ n, point, mine, held, there, side, row, opening }`. A fake squad
## view stands in for the squad.

const MARKERS_SCRIPT := "res://scenes/ui/hud/stack_markers.gd"


func describe() -> Dictionary:
	return {
		"name": "Stack markers draw the slots and the human's own",
		"description": "The markers show every slot of the reserved doorway, flag the human's own, "
			+ "and clear when the reservation ends; and every stack of the human's side from the "
			+ "squad's view, ordered or its own, with no human slot: dim on the way, filled once "
			+ "there, the human's own bright, free faint, both sides and second rows, gone once "
			+ "through (LD18).",
		"tags": ["ui", "hud", "stack"],
		"timeout": 6.0,
	}


func run(t: TestContext) -> void:
	if not t.require(ResourceLoader.exists(MARKERS_SCRIPT), "the stack markers script exists"):
		return
	var markers: Node2D = (load(MARKERS_SCRIPT) as GDScript).new()
	t.world.add_child(markers)
	var stack := FakeStack.new()
	t.world.add_child(stack)
	markers.watch(stack)
	await t.frames(2)
	t.expect_eq((markers.drawn() as Array).size(), 0, "nothing is drawn without a reservation")

	stack.current = {
		"opening": "door_840_190", "door": Vector2(840, 190), "mine": 2, "step": "ready",
		"slots": [
			{ "n": 1, "point": Vector2(868, 253), "mine": false, "held": true },
			{ "n": 2, "point": Vector2(868, 287), "mine": true, "held": true },
			{ "n": 3, "point": Vector2(868, 321), "mine": false, "held": false },
		],
	}
	await t.frames(2)
	var drawn: Array = markers.drawn()
	t.expect_eq(drawn.size(), 3, "every slot of the doorway is drawn")
	var numbers := drawn.map(func(d): return int(d["n"]))
	numbers.sort()
	t.expect_eq(numbers, [1, 2, 3], "each with its number")
	var own := drawn.filter(func(d): return bool(d["mine"]))
	t.check(own.size() == 1 and int(own[0]["n"]) == 2, "only the human's own slot is highlighted")
	for d in drawn:
		if int(d["n"]) == 2:
			t.check(
				(d["point"] as Vector2).is_equal_approx(Vector2(868, 287)),
				"drawn where the slot is",
			)

	stack.current = {}
	await t.frames(2)
	t.expect_eq((markers.drawn() as Array).size(), 0, "the markers clear when the reservation ends")

	await _squad_stacks(t, markers, stack)


## LD18: the stacks of the human's side, read from the squad's view.
func _squad_stacks(t: TestContext, markers: Node2D, stack: FakeStack) -> void:
	if not t.require(
			markers.has_method("watch_squad"),
			"the markers watch the squad's stacks (StackMarkers.watch_squad(view: Callable))",
	):
		return
	var squad := FakeSquad.new()
	markers.watch_squad(squad.view)
	await t.frames(2)
	t.expect_eq(
		(markers.drawn() as Array).size(),
		0,
		"nothing is drawn while the side has no stack",
	)

	# Two teammates' stacks, the human in neither: an ordered one at the back door (the point there,
	# the second on its way, a free slot left by a member that took the back) and the AI's own at
	# the front door, split across it with a second file on its north side.
	var back_door := _back_door()
	var front_door := _front_door()
	squad.current = { "stacks": [back_door, front_door] }
	await t.frames(2)
	_check_teammates_stacks(t, markers.drawn())

	# The human joins the back door's stack: its own slot (3) from its PlayerStack, bright, and
	# drawn once.
	_join_human(back_door, stack)
	squad.current = { "stacks": [back_door, front_door] }
	await t.frames(2)
	_check_human_joined(t, markers.drawn())

	# The front door's stack is through: it leaves the squad's view, and its rings go.
	squad.current = { "stacks": [back_door] }
	await t.frames(2)
	t.expect_eq(
		_of(markers.drawn(), "door_0_415").size(),
		0,
		"a stack's rings go once it is through",
	)
	t.expect_eq(
		_numbers(_of(markers.drawn(), "door_840_190")),
		[1, 2, 3, 4],
		"the one still forming stays",
	)
	stack.current = {}
	squad.current = { "stacks": [] }
	await t.frames(2)
	t.expect_eq((markers.drawn() as Array).size(), 0, "nothing is left once every stack is through")


## The ordered stack at the back door in the squad's view: the point there, the second on its way,
## a free slot left by a member that took the back.
func _back_door() -> Dictionary:
	return {
		"opening": "door_840_190", "into": "kitchen", "door": Vector2(840, 190),
		"slots": _slots([
			[1, Vector2(868, 127), 11, true, true, 1, 1],
			[2, Vector2(868, 83), 12, true, false, 1, 1],
			[3, Vector2(868, 39), 0, false, false, 1, 1],
			[4, Vector2(868, -5), 13, true, false, 1, 1],
		]),
	}


## The AI's own stack at the front door in the squad's view, split across it with a second file on
## its north side.
func _front_door() -> Dictionary:
	return {
		"opening": "door_0_415", "into": "hall", "door": Vector2(0, 415),
		"slots": _slots([
			[1, Vector2(-28, 357), 21, true, true, 1, 1],
			[2, Vector2(-28, 473), 22, true, true, -1, 1],
			[3, Vector2(-72, 357), 23, true, false, 1, 2],
		]),
	}


## The squad view's slots of `rows`, each `[n, point, holder, held, there, side, row]`, none the
## human's (`mine` false).
func _slots(rows: Array) -> Array:
	return rows.map(func(r: Array) -> Dictionary: return {
		"n": r[0], "point": r[1], "holder": r[2], "held": r[3], "there": r[4], "mine": false,
		"side": r[5], "row": r[6],
	})


## The human takes slot 3 of `back_door` (the squad's view, `mine`) and its PlayerStack `stack`
## claims it too.
func _join_human(back_door: Dictionary, stack: FakeStack) -> void:
	back_door["slots"][2] = {
		"n": 3,
		"point": Vector2(868, 39),
		"holder": 99,
		"held": true,
		"there": false,
		"mine": true,
		"side": 1,
		"row": 1,
	}
	stack.current = {
		"opening": "door_840_190", "door": Vector2(840, 190), "mine": 3, "step": "claim",
		"slots": [
			{ "n": 1, "point": Vector2(868, 127), "mine": false, "held": true },
			{ "n": 2, "point": Vector2(868, 83), "mine": false, "held": true },
			{ "n": 3, "point": Vector2(868, 39), "mine": true, "held": true },
			{ "n": 4, "point": Vector2(868, -5), "mine": false, "held": true },
		],
	}


## The two teammates' stacks in `drawn`: every slot, numbered in claim order, none the human's;
## filled, dim and faint by holder; both sides and the second file where their slots are.
func _check_teammates_stacks(t: TestContext, drawn: Array) -> void:
	t.expect_eq(
		drawn.size(),
		7,
		"every slot of both teammates' stacks is drawn, with no human slot in either",
	)
	var at_back := _of(drawn, "door_840_190")
	var at_front := _of(drawn, "door_0_415")
	t.expect_eq(
		_numbers(at_back),
		[1, 2, 3, 4],
		"the ordered stack's rings, numbered in claim order",
	)
	t.expect_eq(_numbers(at_front), [1, 2, 3], "and the AI's own stack's")
	t.check(
		drawn.all(func(d): return not bool(d.get("mine", false))),
		"none is the human's own (none bright)",
	)
	t.check(
		_ring(at_back, 1).get("there") == true and _ring(at_back, 1).get("held") == true,
		"a member standing in its slot: filled (%s)" % str(_ring(at_back, 1)),
	)
	t.check(
		_ring(at_back, 2).get("there") == false and _ring(at_back, 2).get("held") == true,
		"a member on its way: dim (%s)" % str(_ring(at_back, 2)),
	)
	t.check(
		_ring(at_back, 3).get("held") == false,
		"a free slot: faint (%s)" % str(_ring(at_back, 3)),
	)
	t.check(
		_at(_ring(at_back, 4), Vector2(868, -5)),
		"each drawn where its slot is (%s)" % str(_ring(at_back, 4)),
	)
	_check_split_front(t, at_front)


## The front door's split stack in `at_front`: both sides drawn, the other side's ring and the
## second file's where their slots are.
func _check_split_front(t: TestContext, at_front: Array) -> void:
	var sides := at_front.map(func(d): return int(d.get("side", 0)))
	t.check(
		sides.has(1) and sides.has(-1),
		"both sides of a split stack are drawn (sides %s)" % str(sides),
	)
	t.check(
		_at(_ring(at_front, 2), Vector2(-28, 473)),
		"the other side's ring where its slot is (%s)" % str(_ring(at_front, 2)),
	)
	t.check(
		int(_ring(at_front, 3).get("row", 0)) == 2 and _at(_ring(at_front, 3), Vector2(-72, 357)),
		"a second file's ring, a step out (%s)" % str(_ring(at_front, 3)),
	)


## With the human in the back door's stack, `drawn` holds each of its slots once, the human's own
## the only bright one, and the other stack still.
func _check_human_joined(t: TestContext, drawn: Array) -> void:
	var at_back := _of(drawn, "door_840_190")
	t.expect_eq(
		_numbers(at_back),
		[1, 2, 3, 4],
		"the human's stack and the squad's view of it draw each slot once",
	)
	var own := drawn.filter(func(d): return bool(d.get("mine", false)))
	t.check(
		own.size() == 1 and int(own[0]["n"]) == 3 and _at(own[0], Vector2(868, 39)),
		"the human's own slot is bright, and the only one (%s)" % str(own),
	)
	t.expect_eq(
		_numbers(_of(drawn, "door_0_415")),
		[1, 2, 3],
		"the other stack is still drawn meanwhile",
	)


## The rings drawn at doorway `opening`.
func _of(drawn: Array, opening: String) -> Array:
	return drawn.filter(func(d): return String(d.get("opening", "")) == opening)


## The sorted slot numbers of `rings` (duplicates kept, so a slot drawn twice shows).
func _numbers(rings: Array) -> Array:
	var out := rings.map(func(d): return int(d["n"]))
	out.sort()
	return out


## Ring `n` of `rings`, or {}.
func _ring(rings: Array, n: int) -> Dictionary:
	for d in rings:
		if int(d["n"]) == n:
			return d
	return {}


func _at(ring: Dictionary, p: Vector2) -> bool:
	return ring.has("point") and (ring["point"] as Vector2).is_equal_approx(p)


## A stand-in for the human's stack: whatever `view()` it is told to give.
class FakeStack extends Node:
	var current := {}

	func view() -> Dictionary:
		return current


## A stand-in for the squad: whatever `view()` it is told to give (the markers are handed its `view`
## as a Callable).
class FakeSquad extends RefCounted:
	var current := {}

	func view() -> Dictionary:
		return current
