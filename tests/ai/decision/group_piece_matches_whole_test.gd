extends GameTest
## The group piece's stepped build (`SnapshotDemand.group_steps` / `grenade_steps`: the leads, the
## entries while a stun can be thrown, and the throws at the hostile the throw search found one at,
## a lead, a doorway or a grenade kind a step) gives the groups the one-shot build gives, at every
## pace: the options, their wording, the summary and the `lead_pos` the controller radios, with an
## older snapshot completed between the batches of steps (the hazard of a held build,
## `snapshot-staged.md`). Over the throw fixtures of `ai/decision/throw_piece_matches_whole` (the
## Terrace house, an invader with a frag and a stun outside the back door) with gunfire heard in
## several rooms: a hostile at the round jamb (its throws are the target's group), and the hostile
## gone, shots landing (the shots' origin's throws, the shooter lead). A stun in the stack hands the
## leads the entries' rooms, so the entries are built first; without one the leads alone.
##
## Eager reference: the same moment's groups built whole by `demand.group()` / `target_group()`.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const Kind := preload("res://scenes/ai/perception/snapshot/group_build.gd").Kind
const ThrowSearch := preload("res://scenes/ai/perception/snapshot/throw_search.gd")
## Where the invader stands outside the back door, and the householder in the kitchen it sees
## through the doorway off its axis (its lob from the hand clears no jamb: a throw spot is needed).
const I_AT := Vector2(960, 190)
const H_JAMB := Vector2(660, 120)
## Against the kitchen's east wall north of the back door: shots out of the doorway have no clear
## lob into the kitchen from there.
const SHOT_AT := Vector2(875, 100)
const SHOOTER := Vector2(600, 210)
const LANDED := Vector2(930, 210)
## Where gunfire is heard (distinct 200 px cells: a lead each).
const HEARD := [Vector2(300, 300), Vector2(500, 120), Vector2(700, 330)]
## Units of work run between two completions of an older snapshot: one, two, and every one.
const PACES := [1, 2, 1000]


func describe() -> Dictionary:
	return {
		"name": "The group piece's stepped build equals the one-shot build at every pace",
		"description": "The leads, the entries (with a stun in the stack) and the throws at the "
			+ "hostile the search found one at, built a unit at a time by 1, 2 and 1000, equal "
			+ "the groups built whole: options, wording, summary and lead_pos.",
		"tags": ["ai", "decision", "snapshot", "grenade"],
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
	Probe.arm(inv, 0, 1)  # a frag only: no stun in the stack, the leads alone
	await t.frames(3)
	var brain := t.controller(&"i", &"debug_state")
	var perception: Node = brain.get("_perception")
	inv.facing = (H_JAMB - I_AT).normalized()
	if not t.require(await _sees(t, brain), "set-up: the invader sees the householder"):
		return
	for at: Vector2 in HEARD:
		_gunfire(at)
	await t.frames(3)
	_compare(t, brain, perception, "a hostile at the jamb, a frag carried", false)
	_stun_arrives(t, brain, perception)
	Probe.arm(inv, 1, 1)  # a stun in the stack: the entries are built before the leads
	await t.frames(3)
	_compare(t, brain, perception, "a hostile at the jamb, a stun carried", true)
	t.actor(&"h").take_damage(2_000_000.0)
	if not t.require(await _gone(t, brain), "set-up: the invader no longer knows a hostile"):
		return
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
	_compare(t, brain, perception, "the shots' origin", true)


## One moment: the groups built whole, then built stepped at each pace on a snapshot of their own,
## an older snapshot completed between batches. `stun`: a stun in the stack (the entries are built
## and leave their rooms out of the leads).
func _compare(
	t: TestContext, brain: Node, perception: Node, label: String, stun: bool
) -> void:
	var goal: String = brain.get("goal")
	var want := _groups(perception.sense(goal, "", 0)["demand"], false, stun)
	if not stun:
		t.check(
			(want["leads"]["options"] as Array).size() >= 2,
			"%s: the world has leads to build a step each" % label,
		)
	t.check(
		not (want["throws"]["options"] as Array).is_empty(),
		"%s: the world has a throw to build" % label,
	)
	# One count for each group built, whatever the pace (not one a step): on a snapshot of its own,
	# no older one completed beside it.
	var counted: Dictionary = SnapshotCounts.built.duplicate()
	_run(t, perception.sense(goal, "", 0)["demand"].group_steps(), 1, {}, label)
	t.expect_eq(_rise(counted, "leads"), 1, "%s: the leads are counted once" % label)
	t.expect_eq(_rise(counted, "entries"), 1 if stun else 0, "%s: the entries too" % label)
	for pace: int in PACES:
		var tag := "%s, %d at a time" % [label, pace]
		var snap: Dictionary = perception.sense(goal, "", 0)
		var older: Dictionary = perception.sense(goal, "", 0)
		var demand: RefCounted = snap["demand"]
		var units := _run(t, demand.group_steps(), pace, older, tag)
		t.check(units >= 2, "%s: the groups took a step each (%d)" % [tag, units])
		var search: RefCounted = demand.throw_search(16)
		while search != null and search.next_kind() != ThrowSearch.Kind.DONE:
			search.step()
		_run(t, demand.grenade_steps(), pace, older, tag)
		var got := _groups(demand, true, stun)
		for name: String in want:
			t.expect_eq(got[name], want[name], "%s: the %s group" % [tag, name])
		t.expect_eq(
			got["leads"].get("lead_pos"),
			want["leads"].get("lead_pos"),
			"%s: lead_pos" % tag,
		)


## How many builds of `name` were counted since `before` (`SnapshotCounts.built`).
func _rise(before: Dictionary, name: String) -> int:
	return int(SnapshotCounts.built.get(name, 0)) - int(before.get(name, 0))


## The leads built while no stun was in the stack are forgotten when the stack says one is
## (`AgentSnapshot.reread_claims`): the walk then builds the leads the entries' rooms are left out
## of, as a snapshot that had the stun from the start does.
func _stun_arrives(t: TestContext, brain: Node, perception: Node) -> void:
	var goal: String = brain.get("goal")
	var late: RefCounted = perception.sense(goal, "", 0)["demand"]
	var steps: RefCounted = late.group_steps()
	while steps.next_kind() != Kind.DONE:
		steps.step()
	t.check(late.groups.has("leads") and not late.groups.has("entries"), "premise: leads only")
	late.stun_stack = true
	late.forget_leads()
	t.check(not late.groups.has("leads"), "the leads made without the entries are forgotten")
	t.check(not (late.built as Array).has("leads"), "and are no longer listed as built")
	var early: RefCounted = perception.sense(goal, "", 0)["demand"]
	early.stun_stack = true
	t.expect_eq(late.group("leads"), early.group("leads"), "the leads built again are the stun's")


## The steps run `pace` at a time to their end, an older snapshot completed after each batch:
## how many units of work they took (0 for no steps).
func _run(t: TestContext, steps: RefCounted, pace: int, older: Dictionary, tag: String) -> int:
	if steps == null:
		return 0
	var units := 0
	var guard := 0
	while steps.next_kind() != Kind.DONE and guard < 500:
		for i in pace:
			var kind: int = steps.next_kind()
			if kind == Kind.DONE:
				break
			units += 1 if kind == Kind.UNIT else 0
			steps.step()
		if not older.is_empty():
			older["demand"].complete()
		guard += 1
	t.check(guard < 500, "%s: the steps end" % tag)
	return units


## The groups of `demand` as the walk would read them: the leads, the entries (with a stun) and
## the throws (the first hostile's, else the shots'). Built now by the one-shot, or, `held`, as
## stored already.
func _groups(demand: RefCounted, held: bool, stun: bool) -> Dictionary:
	var out := {}
	var throws := {}
	if held:
		out["leads"] = demand.groups["leads"]
		if stun:
			out["entries"] = demand.groups["entries"]
		for id in demand.targets:
			throws = demand.groups["per_target"][id]["grenade_throws"]
		out["throws"] = throws if not throws.is_empty() else demand.groups["grenade_throws"]
		return out
	out["leads"] = demand.group("leads")
	if stun:
		out["entries"] = demand.group("entries")
	throws = demand.group("grenade_throws")
	for id in demand.targets:
		throws = demand.target_group("grenade_throws", id)
	out["throws"] = throws
	return out


## Gunfire heard at `at`.
func _gunfire(at: Vector2) -> void:
	EventBus.post(
		&"hit",
		{
			"position": at, "direction": Vector2.LEFT, "damage": 10.0, "attacker": null,
			"victim": null,
		},
	)


func _sees(t: TestContext, brain: Node) -> bool:
	return await t.until(func() -> bool: return _hostiles(brain) > 0, 3.0)


func _gone(t: TestContext, brain: Node) -> bool:
	return await t.until(func() -> bool: return _hostiles(brain) == 0, 3.0)


func _hostiles(brain: Node) -> int:
	return (brain.debug_state().get("contacts", []) as Array).filter(
		func(c): return c.get("hostile", false)
	).size()
