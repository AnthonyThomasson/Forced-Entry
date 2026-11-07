extends GameTest
## The `grenade_ready` fact (docs/grenades.md G17, G18: a legal throw exists) is answered by a
## search that stops at the first feasible spot, and the full throw options are built only when the
## walk reads them (#192 rule 24). Over the throw-spot fixtures (a lob that clears the jamb only
## from a throw spot, a clear shot, a room held with a clear lob, a killed target, the shots'
## origin, the same for a thrower confined to the house) the fact equals "the full search found
## a throw", and where a throw spot is needed the search routes fewer spots than the full search
## does.
##
## The Terrace house, bare: an invader with a frag and a stun outside the back door, a household
## puppet that is never killed and never shoots. Each fixture reads two snapshots of the same
## moment: one answers `grenade_ready` (its demand), the other builds the full throw groups.

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


func describe() -> Dictionary:
	return {
		"name": "grenade_ready equals the full search and stops early",
		"description": "Over the round-jamb, no-spot, clear-shot, held-room, killed-target, "
			+ "shots-origin and confined-thrower fixtures the cheap `grenade_ready` equals "
			+ "whether the full throw groups hold an option, and the throw-spot search routes "
			+ "fewer spots than the full one.",
		"tags": ["ai", "grenade", "throw_spot", "snapshot"],
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
	var jamb := _compare(t, brain, perception, "round jamb", true)
	t.check(
		jamb["cheap_walks"] >= 1 and jamb["cheap_walks"] < jamb["full_walks"],
		"round jamb: the search routed fewer throw spots (%d) than the full one (%d)"
			% [jamb["cheap_walks"], jamb["full_walks"]],
	)
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
	var confined := _compare(t, brain, perception, "confined thrower", true)
	t.check(
		confined["cheap_walks"] >= 1 and confined["cheap_walks"] < confined["full_walks"],
		"confined thrower: the search routed fewer throw spots (%d) than the full one (%d)"
			% [confined["cheap_walks"], confined["full_walks"]],
	)


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


## One fixture: the cheap `grenade_ready` of one snapshot and the full throw groups of another,
## the walks each computed. Checks them equal and `want` (what the fixture is by the spec of G17),
## and returns `{ cheap_walks, full_walks }`.
func _compare(
		t: TestContext, brain: Node, perception: Node, label: String, want: bool,
) -> Dictionary:
	var views: RefCounted = perception.views.views
	var cheap_snap: Dictionary = perception.sense(brain.get("goal"), "", 0)
	var cheap = cheap_snap["demand"]
	var full = perception.sense(brain.get("goal"), "", 0)["demand"]
	if not t.require(
			full.has_method("target_group") and "targets" in full,
			"%s: the demand builds a target's throw group on demand" % label,
		):
		return { "cheap_walks": -1, "full_walks": -1 }
	var before: int = views.walk_queries
	var ready: bool = cheap.fact("grenade_ready")
	var cheap_walks: int = views.walk_queries - before
	before = views.walk_queries
	var found := _full_search_found(full)
	var full_walks: int = views.walk_queries - before
	t.check(
		ready == found,
		"%s: grenade_ready %s, the full search found %s" % [label, ready, found],
	)
	t.check(ready == want, "%s: a legal throw %s by G17 (got %s)" % [
		label, "exists" if want else "does not exist", ready,
	])
	t.check(
		cheap_snap["facts"].has("grenade_ready"),
		"%s: the fact is in the snapshot once asked" % label,
	)
	return { "cheap_walks": cheap_walks, "full_walks": full_walks }


## Whether the full throw groups of `demand`'s snapshot hold an option: the shots' group or a
## target's (what `grenade_ready` was before it was cheap).
func _full_search_found(demand: RefCounted) -> bool:
	var found := not (demand.group("grenade_throws")["options"] as Array).is_empty()
	for id in demand.targets:
		var group: Dictionary = demand.target_group("grenade_throws", id)
		found = found or not (group["options"] as Array).is_empty()
	return found
