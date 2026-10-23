extends GameTest
## E16 for the human (`docs/tactical-entry.md` E16): the human's slot is kept only while someone
## else holds a place in the stack; when its only teammate there gives the doorway up (radios
## `abort`), nobody is stacking any more and the human's reservation is withdrawn at once, its claim
## radioed `abort`.
##
## The Terrace house's back door. The human (a puppet with the human's stack radio, as Main gives
## it) stands beside the door's stack. One teammate (`a`) claims slot 1; the human is reserved slot
## 2 behind it and keeps it while `a` stays on the radio; then `a` radios `abort`.
##
## The withdrawal must come well before `PlayerStack.go_timeout` (6 s, E16), the other way a
## reservation with nobody ahead still on the radio ends: so it is the "nobody stacking" rule that
## withdrew it, not the human failing to follow.
##
## Premise: the teammate is a puppet radioing its claims on the bus (`Stack.radio`), not an AI
## invader. An AI's abort comes from its own decisions (a new order, a blocked way), which a test
## cannot time; the human's stack reads only the bus, so a puppet's `abort` is exactly what it hears
## from an AI.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## How often (s) the puppet repeats its claim (the NPCs' heartbeat is 2 s; a claim lapses after
## 6 s).
const REPEAT := 1.0
## How long (s) the teammate stays on the radio with the human reserved, before it aborts.
const HOLD := 3.0
## The most (s) the withdrawal may take after the teammate's abort: well under the spec's
## `go_timeout` (6 s), so the go timeout cannot be what ended it.
const PROMPT := 1.0


func describe() -> Dictionary:
	return {
		"name": "The human's slot is withdrawn once its only teammate in the stack aborts",
		"description": "One teammate (a puppet on the radio) stacks at the back door and the "
			+ "human is reserved slot 2 behind it; the teammate radios abort and the human's "
			+ "reservation is withdrawn at once, its claim radioed abort.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.switch(&"ai.hostile_on_trespass", false)
	Stack.human(s, &"a", Vector2(1150, 40))
	Stack.human(s, &"me", Stack.NEAR)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var opening := String(door["id"])
	var into := String(door["room_key"])
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	if not t.require(
			await _radioing(t, opening, into, func(): return Stack.mine(stack) > 0, 5.0),
			"the human is reserved a slot at the back door",
	):
		return
	t.expect_eq(Stack.mine(stack), 2, "behind the teammate: slot 2")
	var aborted := func(): return not Entry.calls(t, "abort", &"me").is_empty()
	await _radioing(t, opening, into, func(): return aborted.call(), HOLD)
	if not t.require(
			not aborted.call() and Stack.mine(stack) == 2,
			"set-up: the human keeps its slot while its teammate stacks (%.0f s)" % HOLD,
	):
		return
	Stack.radio(t, &"a", opening, into, 1, 1, "abort")
	var at := t.time
	t.check(
		await t.until(aborted, PROMPT),
		"the human's claim is withdrawn within %.0f s of its teammate's abort: it radios abort"
			% PROMPT,
	)
	t.check(Stack.view(stack).is_empty(), "the human has no reservation left")
	t.trace("withdrawn after", t.time - at)


## Keep the teammate `a` radioing its claim on slot 1 of `opening` into `into` every `REPEAT` s
## until `done` holds or `within` s have passed; whether it held.
func _radioing(
	t: TestContext,
	opening: String,
	into: String,
	done: Callable,
	within: float,
) -> bool:
	var start := t.time
	var said := -INF
	while not done.call():
		if t.time - start > within:
			return false
		if t.time - said >= REPEAT:
			said = t.time
			Stack.radio(t, &"a", opening, into, 1, 1)
		await t.frames(1)
	return true
