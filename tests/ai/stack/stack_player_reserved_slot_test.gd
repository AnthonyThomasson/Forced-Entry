extends GameTest
## Desired (E16): a human invader standing near the doorway an AI invader is stacking at is given
## the first free slot (slot 2, behind the AI point) on the AI's side of the door, over the radio,
## and the stack shows it where to stand. The human's claim is a full one, as an NPC's: it carries
## the physics frame it was made on and the spot the human stood on then (`claim_frame`,
## `claim_pos`: same-frame claims settle by distance, E2), kept by the heartbeat however the human
## has moved since, and says `bang: true` and `stuns: 0` (it never holds a stack back, and throws
## nothing for it).
##
## Its `callout_range` and `callout_ttl` reach the claims it hears whenever they are set (as the
## NPCs' exports do): set after `attach`, a range shorter than the human's distance to its teammate
## hears none of the teammate's claims after that, and a ttl of `LONG_TTL` keeps its last one live
## for that long. So the human keeps its slot `KEPT_FOR` s on, past a claim's default ttl (6 s), and
## its reservation is withdrawn (nobody heard stacking) once that last claim lapses.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## The ttl (s) the human's stack is given after `attach`, and how long (s) after its range is cut
## its slot is still kept: past a claim's default ttl (6 s) and its teammate's 2 s heartbeat, within
## `LONG_TTL` less that heartbeat.
const LONG_TTL := 12.0
const KEPT_FOR := 8.5
## The most (s) past `LONG_TTL` the withdrawal may take (a few physics frames).
const LAPSE_SLACK := 1.0


func describe() -> Dictionary:
	return {
		"name": "A nearby human is given the next stack slot",
		"description": "An AI invader stacks at the back door; the human invader near it is "
			+ "reserved slot 2, on the same side, on the radio and in its view.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	# A long ready timeout so the point is still waiting in its stack while the reservation is read,
	# and through the range and ttl checks after it.
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": 60.0 })
	Stack.human(s, &"me", Stack.NEAR)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	if not t.require(
			await t.until(func(): return Stack.mine(stack) > 0, 30.0),
			"the human was reserved a slot (act %s)" % Entry.brain(t, &"a").current_act(),
	):
		return
	var v := Stack.view(stack)
	t.expect_eq(
		str(v.get("opening", "")),
		door["id"],
		"the reservation is at the doorway the AI stacks at",
	)
	t.expect_eq(
		Stack.mine(stack),
		2,
		"the human is reserved the first free slot, behind the AI point",
	)
	var point := Stack.slot_point(stack, 2)
	t.check(
		point != Vector2.INF and Entry.beside_door(door, point),
		"the human's slot is against the wall beside the door (%s)" % point,
	)
	var held := (v.get("slots", []) as Array).filter(
		func(s): return bool(s["held"]) and not bool(s["mine"]),
	)
	t.check(held.size() == 1 and int(held[0]["n"]) == 1, "slot 1 is shown as held by the AI point")
	var mine_slots := (v.get("slots", []) as Array).filter(func(s): return bool(s["mine"]))
	t.check(
		mine_slots.size() == 1 and int(mine_slots[0]["n"]) == 2,
		"exactly the human's own slot is flagged mine",
	)
	var ai_claims := Entry.calls(t, "claim", &"a")
	var my_claims := Entry.calls(t, "claim", &"me")
	if not t.require(
			not ai_claims.is_empty() and not my_claims.is_empty(),
			"both radioed a claim (the human's is on the radio like an NPC's)",
	):
		return
	t.expect_eq(int(ai_claims[0].get("slot", 0)), 1, "the AI took slot 1")
	t.expect_eq(int(my_claims[0].get("slot", 0)), 2, "the human's claim is slot 2")
	t.expect_eq(
		str(my_claims[0].get("opening", "")),
		door["id"],
		"the human's claim names the doorway",
	)
	t.expect_eq(
		int(my_claims[0].get("side", 0)),
		int(ai_claims[0].get("side", 0)),
		"on the AI's side of the door",
	)
	var first: Dictionary = my_claims[0]
	t.check(
		int(first.get("claim_frame", -1)) >= 0,
		"the human's claim says the frame it was made on (%s)" % first.get("claim_frame"),
	)
	var made_at = first.get("claim_pos", Vector2.INF)
	t.check(
		made_at is Vector2 and (made_at as Vector2).distance_to(Stack.NEAR) < 2.0,
		"and where the human stood then (claim_pos %s, it stood at %s)"
			% [first.get("claim_pos"), Stack.NEAR],
	)
	t.check(
		first.has("bang") and bool(first["bang"]),
		"it says bang: true (it holds no stack back)",
	)
	t.check(first.has("stuns") and int(first["stuns"]) == 0, "and stuns: 0 (it throws nothing)")
	# A few steps toward its slot (still a claim, not in it): the heartbeat repeats the claim as it
	# was made. The puppet stops within its `arrive_distance` (6 px) of where it walks to.
	var toward := Stack.NEAR.move_toward(point, 40.0)
	if not t.require(await Stack.walk(t, &"me", [toward], 5.0), "the human steps toward its slot"):
		return
	var said := my_claims.size()
	var repeated := func(): return Entry.calls(t, "claim", &"me").size() > said
	if not t.require(await t.until(repeated, 5.0), "the human's claim is repeated (heartbeat)"):
		return
	var again: Dictionary = Entry.calls(t, "claim", &"me")[-1]
	t.expect_eq(
		int(again.get("claim_frame", -2)),
		int(first.get("claim_frame", -1)),
		"the repeat keeps the frame the claim was made on",
	)
	t.check(
		again.get("claim_pos") == first.get("claim_pos")
			and (again["position"] as Vector2).distance_to(toward) <= 6.0,
		"and the spot it was made from, not where the human stands now (%s, now at %s)"
			% [again.get("claim_pos"), again.get("position")],
	)
	# The exports set after `attach`: a range short of the teammate (none of its claims heard from
	# now on) and a long ttl (its last one heard stays live that long).
	var gap: float = t.actor(&"me").global_position.distance_to(t.actor(&"a").global_position)
	if not t.require(gap > 2.0, "set-up: the human stands apart from its teammate (%.0f px)" % gap):
		return
	stack.set("callout_ttl", LONG_TTL)
	stack.set("callout_range", gap * 0.5)
	var cut := t.time
	var aborted := func(): return not Entry.calls(t, "abort", &"me").is_empty()
	var a_crossed := func(): return not Entry.calls(t, "going_in", &"a").is_empty()
	await t.until(aborted, KEPT_FOR)
	t.check(
		not aborted.call() and Stack.mine(stack) == 2,
		"with callout_ttl %.0f s the human still hears its teammate's last claim %.1f s on: slot 2"
			% [LONG_TTL, KEPT_FOR],
	)
	t.check(
		await t.until(aborted, LONG_TTL - KEPT_FOR + LAPSE_SLACK),
		("with callout_range %.0f px the teammate's claims are not heard: its last one lapses and "
				+ "the human's reservation is withdrawn within %.0f s (abort)")
			% [gap * 0.5, LONG_TTL + LAPSE_SLACK],
	)
	t.trace("withdrawn after the range cut", t.time - cut)
	t.check(
		not a_crossed.call(),
		"set-up: the teammate is still in its stack (no going_in), so nothing else withdrew it",
	)
