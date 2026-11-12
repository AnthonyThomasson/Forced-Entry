extends GameTest
## The throw piece's search for a throw (`SnapshotDemand.throw_search`: the `grenade_ready` fact in
## steps of a count of raw candidates, then the rank pass, then one route a step) gives the answer
## the one-shot search gives, at every step size: the fact the one-shot search answers
## (`fact("grenade_ready")`), "the full throw groups hold an option" (what a throw is, by G17 /
## G18) and the spec's own answer for the fixture, over the throw-spot fixtures of
## `ai/grenade/grenade_ready_matches_full_search` (a lob that clears the jamb only from a throw
## spot, a clear shot, a room held with a clear lob, a killed target, the shots' origin, the same
## for a thrower confined to the house). A smaller step takes more steps; an older snapshot
## completed between the steps leaves the search as it was; and what the search worked out is
## shared with the full groups built after it.
##
## The Terrace house, bare: an invader with a frag and a stun outside the back door, a household
## puppet that is never killed and never shoots.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
## Where the invader stands outside the back door, and the householder in the kitchen it sees
## through the doorway off its axis (its lob from the hand clears no jamb: a throw spot is needed).
const I_AT := Vector2(960, 190)
const H_JAMB := Vector2(660, 120)
## In the kitchen just inside the doorway, on the invader's axis: a clear lob from where it stands.
const H_HELD := Vector2(780, 190)
## In the garden beside the invader, in the open: the same room, a clear shot.
const H_CLEAR := Vector2(1060, 190)
## Against the kitchen's east wall north of the back door, where the shots out of the doorway have
## no clear lob into the kitchen from.
const SHOT_AT := Vector2(875, 100)
## Far out in the garden: the householder it last saw is out of throw range and every throw spot
## in reach of it lies further than a short walk from here.
const FAR := Vector2(1500, 190)
const SHOOTER := Vector2(600, 210)
const LANDED := Vector2(930, 210)
## The throw search's kinds of step (`ThrowScan.Kind`): a block of candidates, the rank pass, a
## route, the end.
const Kind := preload("res://scenes/ai/perception/throw_scan.gd").Kind
## The step sizes (raw candidates a block step works through): one at a time, an odd size, the
## default and more than any search has.
const SIZES := [1, 7, 16, 1000]


func describe() -> Dictionary:
	return {
		"name": "The throw piece's stepped search equals the whole one at every step size",
		"description": "Over the round-jamb, no-spot, clear-shot, held-room, killed-target, "
			+ "shots-origin and confined-thrower fixtures the throw search stepped by 1, 7, 16 "
			+ "and 1000 raw candidates answers as the whole search and the full throw groups do.",
		"tags": ["ai", "decision", "grenade", "throw_spot", "snapshot"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"i", &"invader", I_AT, { "movement:speed": 0.0, "facing": Vector2.LEFT })
	GrenadeAi.hostile(s, &"h", H_JAMB, Maps.DOOR_BACK)
	s.set_props(
		&"i",
		"GoalController",
		{
			"tuning:decision:decide_interval": 1000.0,
			"tuning:decision:tactic_interval": 1000.0,
			"tuning:decision:max_commit_time": 1000.0,
		},
	)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 1, 1)
	await t.frames(3)
	var brain := t.controller(&"i", &"debug_state")
	var perception: Node = brain.get("_perception")
	var h := t.actor(&"h")
	inv.facing = (H_JAMB - I_AT).normalized()
	if not t.require(await _sees(t, brain), "set-up: the invader sees the householder"):
		return
	_compare(t, brain, perception, "round jamb", true)
	inv.global_position = FAR
	await t.frames(3)
	_compare(t, brain, perception, "no throw spot in reach", false)
	inv.global_position = I_AT
	h.global_position = H_HELD
	inv.facing = Vector2.LEFT
	await t.frames(3)
	_compare(t, brain, perception, "held room, clear lob", true)
	h.global_position = H_CLEAR
	inv.facing = Vector2.RIGHT
	await t.frames(3)
	_compare(t, brain, perception, "clear shot", false)
	h.take_damage(2_000_000.0)
	if not t.require(await _gone(t, brain), "set-up: the invader no longer knows a hostile"):
		return
	_compare(t, brain, perception, "killed target", false)
	inv.global_position = SHOT_AT
	inv.facing = Vector2.UP
	EventBus.post(
		&"hit",
		{
			"position": LANDED, "direction": (LANDED - SHOOTER).normalized(), "damage": 10.0,
			"attacker": null, "victim": null,
		},
	)
	await t.frames(3)
	_compare(t, brain, perception, "shots origin", true)
	await _confined(t, brain, perception)


## The shots-origin fixture again for a thrower held to the house (`defend_territory`: confinement
## `inside_only`, which judges an option where it acts, `perception.md`): the fact still equals the
## full search, which finds a throw from a spot.
func _confined(t: TestContext, brain: Node, perception: Node) -> void:
	brain.tuning.decision.defend_territory = true
	await t.frames(3)
	if not t.require(
		perception.confinement.inside_only, "set-up: the thrower is held to the house"
	):
		return
	_compare(t, brain, perception, "confined thrower", true)


## Whether the invader knows a hostile now (waits for sight).
func _sees(t: TestContext, brain: Node) -> bool:
	return await t.until(func() -> bool: return _hostiles(brain) > 0, 3.0)


## Whether the invader has no hostile left.
func _gone(t: TestContext, brain: Node) -> bool:
	return await t.until(func() -> bool: return _hostiles(brain) == 0, 3.0)


func _hostiles(brain: Node) -> int:
	return (brain.debug_state().get("contacts", []) as Array).filter(
		func(c): return c.get("hostile", false)
	).size()


## One fixture: the one-shot answer, the full groups' and, per step size, the stepped search's,
## each on a snapshot of its own of the same moment. Checks them equal and `want` (what the
## fixture is by the spec of G17). Returns `{ steps }` by size.
func _compare(
		t: TestContext, brain: Node, perception: Node, label: String, want: bool,
) -> void:
	var goal: String = brain.get("goal")
	var whole: bool = perception.sense(goal, "", 0)["demand"].fact("grenade_ready")
	var full := _full_search_found(perception.sense(goal, "", 0)["demand"])
	t.check(whole == want, "%s: a legal throw %s by G17 (the one-shot search says %s)" % [
		label, "exists" if want else "does not exist", whole,
	])
	t.check(full == want, "%s: the full throw groups %s a throw" % [
		label, "hold" if want else "hold no",
	])
	var steps := {}
	for size: int in SIZES:
		steps[size] = _stepped(t, perception, size, want, label)
	if steps[1] >= 0:
		t.check(
			steps[1] >= steps[7] and steps[7] >= steps[16] and steps[16] >= steps[1000],
			"%s: a smaller step takes at least as many steps (%s)" % [label, steps],
		)


## The throw search of one snapshot stepped by `size` raw candidates to its end: its answer is
## `want`, it is in the snapshot's facts, an older snapshot completed between the steps changes
## nothing, and the full groups built on the same snapshot after agree. Returns how many steps it
## took (-1: not run).
func _stepped(t: TestContext, perception: Node, size: int, want: bool, label: String) -> int:
	var goal: String = t.controller(&"i", &"debug_state").get("goal")
	var tag := "%s, %d at a time" % [label, size]
	var snap: Dictionary = perception.sense(goal, "", 0)
	var older: Dictionary = perception.sense(goal, "", 0)
	var demand: RefCounted = snap["demand"]
	var search: RefCounted = demand.throw_search(size)
	if not t.require(search != null, "%s: a search is begun" % tag):
		return -1
	t.check(not snap["facts"].has("grenade_ready"), "%s: the fact is not known before" % tag)
	var kinds: Array = []
	var guard := 0
	while search.next_kind() != Kind.DONE and guard < 500:
		kinds.append(search.next_kind())
		search.step()
		older["demand"].complete()
		guard += 1
	t.check(guard < 500, "%s: the search ends" % tag)
	t.expect_eq(search.found, want, "%s: the answer" % tag)
	t.expect_eq(snap["facts"].get("grenade_ready"), want, "%s: the fact the planner finds" % tag)
	t.expect_eq(_full_search_found(demand), want, "%s: the full groups after it" % tag)
	return kinds.size()


## Whether the full throw groups of `demand`'s snapshot hold an option: the shots' group or a
## target's (what `grenade_ready` was before it was cheap).
func _full_search_found(demand: RefCounted) -> bool:
	var found := not (demand.group("grenade_throws")["options"] as Array).is_empty()
	for id in demand.targets:
		var group: Dictionary = demand.target_group("grenade_throws", id)
		found = found or not (group["options"] as Array).is_empty()
	return found
