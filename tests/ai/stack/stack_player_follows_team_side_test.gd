extends GameTest
## E19 for the human (`docs/tactical-entry.md` E16, E19): the side the human is reserved on follows
## the side the team stacks on, the point's, when it changes: weighed again from where the human
## stands, it takes the team's side when its way there does not cross the doorway's view, and
## radios its claim on that side.
##
## The Terrace house's back door. The human (a puppet with the human's stack radio, as Main gives
## it) stands out in front of the door, in its view, south of its axis: a walk from inside the view
## crosses no view, so it stacks on whichever side the team does. The point (`a`, slot 1) and `b`
## (slot 2) claim one side; the human is reserved slot 3 on it; then the point's claim moves to the
## other side.
##
## Premise: the teammates are puppets radioing their claims on the bus (`Stack.radio`), not AI
## invaders. The side the human weighed only changes when the slot-1 claim it hears changes side
## after its reservation, which with AI teammates takes the human hearing another claim before the
## point's (a race on the radio's heartbeat) or an AI point changing sides. The human's stack reads
## only the bus, so a puppet's claim is exactly what it hears from an AI.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## Where the human stands: 140 px out in front of the back door, 35 px south of its axis (in the
## door's view, out of its funnel).
const HUMAN := Vector2(980, 225)
## How often (s) the puppets repeat their claims (the NPCs' heartbeat is 2 s; a claim lapses after
## 6 s).
const REPEAT := 1.0


func describe() -> Dictionary:
	return {
		"name": "The human's stack side follows the team's when the point's side changes",
		"description": "Two teammates (puppets on the radio) stack on one side of the back door "
			+ "and the human is reserved slot 3 there; the point's claim moves to the other side "
			+ "and the human, its way there clear of the doorway's view, radios its claim on that "
			+ "side, its slot kept.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.switch(&"ai.hostile_on_trespass", false)
	Stack.human(s, &"a", Vector2(1150, 40))
	Stack.human(s, &"b", Vector2(1150, 80))
	Stack.human(s, &"me", HUMAN)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var opening := String(door["id"])
	var into := String(door["room_key"])
	if not t.require(
			absf(Entry.lateral(door, HUMAN)) < float(door["width"]) * 0.5
				and Entry.outward(door, HUMAN) > Entry.FUNNEL_DEPTH,
			"set-up: the human stands in front of the doorway, out of its funnel",
	):
		return
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	# The point's side first: 1 along the wall (the radio's terms, whichever side that is).
	var claiming := { &"a": [1, 1], &"b": [2, 1] }
	if not t.require(
			await _radioing(t, claiming, opening, into, func(): return Stack.mine(stack) > 0),
			"the human is reserved a slot at the back door",
	):
		return
	t.expect_eq(Stack.mine(stack), 3, "behind the two: slot 3")
	var first := Stack.calls_at(t, &"me", opening)
	if not t.require(
			not first.is_empty() and int(first[-1].get("side", 0)) == 1,
			"set-up: the human's claim is on the team's side, 1 (it radioed %s)"
				% (str(first[-1].get("side")) if not first.is_empty() else "nothing"),
	):
		return
	var said := first.size()
	# The point's claim moves to the other side of the door.
	claiming[&"a"] = [1, -1]
	var follows := func():
		var calls := Stack.calls_at(t, &"me", opening)
		return calls.size() > said and int(calls[-1].get("side", 0)) == -1
	t.check(
		await _radioing(t, claiming, opening, into, follows),
		"the human radios its claim on the point's new side, -1",
	)
	var last := Stack.calls_at(t, &"me", opening)
	t.expect_eq(String(last[-1].get("entry_step", "")), "claim", "still a claim, not withdrawn")
	t.expect_eq(int(last[-1].get("slot", 0)), 3, "its slot kept: 3")
	t.expect_eq(Stack.mine(stack), 3, "and shown in its view")


## Keep the puppets in `claiming` (id -> [slot, side]) radioing their claims on `opening` into
## `into` every `REPEAT` s until `done` holds or 5 s have passed; whether it held.
func _radioing(
	t: TestContext,
	claiming: Dictionary,
	opening: String,
	into: String,
	done: Callable,
) -> bool:
	var start := t.time
	var said := -INF
	while not done.call():
		if t.time - start > 5.0:
			return false
		if t.time - said >= REPEAT:
			said = t.time
			for id in claiming:
				Stack.radio(t, id, opening, into, claiming[id][0], claiming[id][1])
		await t.frames(1)
	return true
