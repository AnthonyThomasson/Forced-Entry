extends GameTest
## The reads an entry keeps (#194) answer as a fresh one would, every frame of a team's
## entry: each NPC's own claim (`EntryClaim.me`, kept while the member's fields and terms stand)
## against one a brand-new claim part builds with nothing kept, and each read its doorway stack
## keeps for it (`DoorStack.mode`, `hold`, `held`, `order_claim`, `points`, `crossing`, `thrower`)
## against the stack working it out again. A kept read gone stale (a slot taken, a go latched, a
## grenade thrown that the key did not see) fails it.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const EntryClaim := preload("res://scenes/ai/behavior/entry/entry_claim.gd")
const IDS := [&"a", &"b", &"c", &"d"]
## Seconds the team is watched (it stacks at the back door and goes in).
const WATCH := 50.0


func describe() -> Dictionary:
	return {
		"name": "Kept entry reads match a fresh recompute every frame",
		"description": "Four invaders stack at the back door and go in: each frame every entry's "
			+ "claim and each stack read it keeps equals what is worked out afresh.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 40), { "tuning:entry:ready_timeout": 30.0 })
	Entry.npc(
		s, &"b", Vector2(985, 100),
		{ "tuning:decision:decide_interval": 0.55, "tuning:entry:ready_timeout": 30.0 },
	)
	Entry.npc(
		s, &"c", Vector2(990, 280),
		{ "tuning:decision:decide_interval": 0.7, "tuning:entry:ready_timeout": 30.0 },
	)
	Entry.npc(
		s, &"d", Vector2(1010, 200),
		{ "tuning:decision:decide_interval": 0.65, "tuning:entry:ready_timeout": 30.0 },
	)


func run(t: TestContext) -> void:
	var entries: Array = []
	for id in ids():
		var brain: Node = Entry.brain(t, id)
		if brain != null:
			entries.append(brain.get("_behavior").get("_entry"))
	if not t.require(entries.size() == ids().size(), "every NPC has an entry part"):
		return
	var bad: Array[String] = []
	var tally := [0, 0, 0, 0, 0, 0]
	var until := t.time + WATCH
	while t.time < until and bad.size() < 4 and not _done(t):
		await t.frames(1)
		_frame(t)
		for entry: RefCounted in entries:
			_check(entry, bad, tally)
	t.check(bad.is_empty(), "kept reads equal fresh ones: %s" % str(bad.slice(0, 4)))
	t.check(tally[0] > 100, "premise: entries were running (%d checks)" % tally[0])
	t.check(tally[1] > 0, "premise: a stack with claims in it was read (%d)" % tally[1])
	_premises(t, tally)


## The NPCs whose entries are watched.
func ids() -> Array:
	return IDS


## Whether the watch is over: every NPC has gone in.
func _done(t: TestContext) -> bool:
	return ids().all(func(id): return not Entry.calls(t, "in", id).is_empty())


## Called each frame before the entries are checked: what a case does to its world while it is
## watched.
func _frame(_t: TestContext) -> void:
	pass


## The premises of the case on `tally` (`_check`): which reads the watch met.
func _premises(t: TestContext, tally: Array) -> void:
	t.check(
		tally[2] > 0,
		"premise: a stack was ordered or held for a go at some frame (%d)" % tally[2],
	)


## One running `entry`: its claim and its stack's reads against fresh ones, what differs added to
## `bad`; `tally` counts the entries checked, those with claims on their doorway and those with a
## mode set, a hold, a held read true and an order claim (each tallied apart).
func _check(entry: RefCounted, bad: Array[String], tally: Array) -> void:
	if entry.state.phase in ["", "done"] or entry.state.geo.is_empty():
		return
	tally[0] += 1
	var me: Dictionary = entry.claim.me(entry)
	var fresh := EntryClaim.new(entry.state, entry.world)
	# Its own, so the kept claim's caches are not touched: the terms it writes are equal values.
	var terms_before: Dictionary = entry.state.member.terms
	var built: Dictionary = fresh.me(entry)
	entry.state.member.terms = terms_before
	if built != me:
		bad.append(
			"frame %d claim %s, fresh %s" % [Engine.get_physics_frames(), str(me), str(built)],
		)
	var stack: RefCounted = entry.claim.stack
	if not stack.team.is_empty():
		tally[1] += 1
	if stack.mode(me) != "":
		tally[2] += 1
	if not stack.hold(me).is_empty():
		tally[3] += 1
	if stack.held(me):
		tally[4] += 1
	if not stack.order_claim(me).is_empty():
		tally[5] += 1
	var reads := {
		"mode": [stack.mode(me), stack._mode(me)],
		"hold": [stack.hold(me), stack._hold(me)],
		"held": [stack.held(me), stack._held(me)],
		"order_claim": [stack.order_claim(me), stack._order_claim(me)],
		"points": [stack.points(me), stack._points(me)],
		"crossing": [stack.crossing(me), stack._crossing(me)],
		"thrower": [stack.thrower(&"stun", me), stack._thrower(me, &"stun")],
		"thrower_frag": [stack.thrower(&"frag", me), stack._thrower(me, &"frag")],
	}
	for key: String in reads:
		var kept: Variant = _plain(reads[key][0])
		var again: Variant = _plain(reads[key][1])
		if kept != again:
			bad.append("frame %d %s: %s" % [Engine.get_physics_frames(), key, _diff(kept, again)])


## `read` as the stack's contract has it: a claim's `age` (the seconds since it was heard, which the
## ledger moves on in place every frame) is no part of a row a kept read hands out, and no reader
## of one looks at it.
func _plain(read: Variant) -> Variant:
	if read is Array:
		return read.map(_plain)
	if read is Dictionary:
		var out := {}
		for k in read:
			if k != "age":
				out[k] = _plain(read[k])
		return out
	return read


## Where `kept` and `fresh` differ, as a short text: the first differing key of the first differing
## row of two arrays of dictionaries, else both values.
func _diff(kept: Variant, fresh: Variant) -> String:
	if kept is Array and fresh is Array and kept.size() == fresh.size():
		for i in kept.size():
			if kept[i] != fresh[i] and kept[i] is Dictionary and fresh[i] is Dictionary:
				return "row %d: %s" % [i, _key_diff(kept[i], fresh[i])]
	return "kept %s, fresh %s" % [str(kept).left(300), str(fresh).left(300)]


## The first key of dictionaries `kept` and `fresh` that differs, with both values.
func _key_diff(kept: Dictionary, fresh: Dictionary) -> String:
	for k in kept:
		if kept[k] != fresh.get(k):
			return "key %s: kept %s, fresh %s" % [k, kept[k], fresh.get(k)]
	return "kept %s, fresh %s" % [str(kept).left(200), str(fresh).left(200)]
