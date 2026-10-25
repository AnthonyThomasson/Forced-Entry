extends GameTest
## E16 / E17 for the human (`docs/tactical-entry.md`; `docs/leadership.md` LD14, LD17): a member
## of a stack on its `bang` step is still stacking. The human leader orders its one AI teammate to
## stack with a stun at the Terrace house's back door, beside which the human stands; the human is
## reserved the slot behind the AI's and stands in it. Through the AI's whole bang, from its `bang`
## call until the stun goes off, the human keeps its slot in its view and radios no `abort`: the
## stack it stands in is still forming, its only other member at the bang.
##
## The whole AI pipeline with the real Von server; the human is a puppet with the invader faction,
## given the stack radio and its squad the way a match gives them (`MatchBuilder.bind_player` and
## `bind_squad`, through `s.squads`), leading the squad. The AI carries one stun (armed as Main arms
## a loadout): the premise of a stun entry.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Grenade := preload("res://tests/_ai/grenade_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## The longest (s) the bang may take from its call to the burst (the stack's own cap is 5 s).
const BANG_CAP := 10.0


func describe() -> Dictionary:
	return {
		"name": "The human keeps its slot through its teammate's bang",
		"description": "The human leader orders one AI to stack on the back door with a stun and "
			+ "stands in the slot behind it; through the AI's bang, from its call to the burst, "
			+ "the human's slot stays in its view and it radios no abort.",
		"tags": ["ai", "entry", "stack", "grenade", "leadership", "von", "callout"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"invader", Vector2(960, 60))
	Stack.human(s, &"me", Vector2(1000, 120))
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var door: Dictionary = Entry.BACK
	var opening := String(door["id"])
	Grenade.arm(t.actor(&"a"), 1)
	var squad := t.squad(&"invader")
	var stack := t.player_stack()
	if not t.require(stack != null, "the human has a stack radio (MatchBuilder.bind_player)"):
		return
	await t.seconds(0.3)
	if not await _reserved_in_stun_stack(t, squad, stack):
		return
	var mine := Stack.mine(stack)
	if not t.require(
			await Stack.walk(t, &"me", [Stack.slot_point(stack, mine)], 15.0),
			"the human walks to its slot %d" % mine,
	):
		return
	if not await _bang_called(t, opening):
		return
	await _check_kept(t, stack, mine, opening)


func _reserved_in_stun_stack(t: TestContext, squad: Node, stack: Node) -> bool:
	var order := Order.stack_order(squad, [t.actor(&"a")], Order.BACK_NORTH, "stun", false)
	if not t.require(not order.is_empty(), "the squad posts the stun stack order (issue)"):
		return false
	var settled := [0, 0]  # The human's slot last frame, and the frames it has held it.
	var reserved := func():
		var now := Stack.mine(stack)
		settled[1] = settled[1] + 1 if now == settled[0] and now > 0 else 0
		settled[0] = now
		return settled[1] >= 20
	return t.require(
		await t.until(reserved, 30.0),
		"the human is reserved a slot at the back door (act %s)" % Entry.brain(
			t,
			&"a",
		).current_act(),
	)


func _bang_called(t: TestContext, opening: String) -> bool:
	var called := func(): return not Entry.calls(t, "bang", &"a").is_empty()
	return t.require(
		await t.until(called, 40.0),
		"the AI calls the bang (premise: it throws the stack's stun; act %s, its steps %s)"
			% [
				Entry.brain(t, &"a").current_act(),
				str(Stack.calls_at(t, &"a", opening).map(func(d): return d["entry_step"])),
			],
	)


func _check_kept(t: TestContext, stack: Node, mine: int, opening: String) -> void:
	var kept := [true, ""]  # Whether the human kept its slot every frame, and the first lapse.
	var burst := func():
		if Stack.mine(stack) != mine and kept[0]:
			kept[0] = false
			kept[1] = "at %.2f s its view showed slot %d" % [t.time, Stack.mine(stack)]
		return t.happened(&"explosion", func(d): return d.get("kind") == &"stun")
	if not t.require(
			await t.until(burst, BANG_CAP),
			"the AI's stun goes off (its steps %s)"
				% str(Stack.calls_at(t, &"a", opening).map(func(d): return d["entry_step"])),
	):
		return
	t.check(kept[0], "the human keeps slot %d through the bang (%s)" % [mine, kept[1]])
	t.check(
		Entry.calls(t, "abort", &"me").is_empty(),
		"the human radios no abort through the bang (its steps %s)"
			% str(Stack.calls_at(t, &"me", opening).map(func(d): return d["entry_step"])),
	)
