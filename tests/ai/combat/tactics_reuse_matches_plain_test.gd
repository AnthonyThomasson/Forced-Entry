extends GameTest
## Candidate geometry reused inside one frozen two-target snapshot is identical to the plain scan:
## same fire, flank and advance groups, with fewer route and cover queries. Whole snapshots,
## completed (every group, fact and section, each hostile's sections and the order the groups and
## hostiles come in), equal the plain computation's for an invader carrying a frag and a stun with
## two hostiles in view.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
## Where the invader stands outside the back door, and the two householders it sees in the kitchen.
const I_AT := Vector2(960, 190)
const H1_AT := Vector2(660, 120)
const H2_AT := Vector2(700, 270)


func describe() -> Dictionary:
	return {
		"name": "Two-target tactics reuse matches the plain computation",
		"description": "Snapshot-scoped routes and per-point, per-hostile cover facts preserve "
			+ "every option and its order while repeated geometry is queried once.",
		"tags": ["ai", "combat", "tactics"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	s.actor(&"npc", &"puppet", Maps.HALL_MIDDLE)
	s.actor(&"one", &"puppet", Maps.LIVING_CENTRE)
	s.actor(&"two", &"puppet", Maps.KITCHEN_CENTRE)
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"i", &"invader", I_AT, { "movement:speed": 0.0, "facing": Vector2.LEFT })
	GrenadeAi.hostile(s, &"h1", H1_AT, Maps.DOOR_BACK)
	GrenadeAi.hostile(s, &"h2", H2_AT, Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	await t.frames(2)
	var hostiles: Array = [_contact(t.actor(&"one")), _contact(t.actor(&"two"))]
	var plain_tactics := _tactics()
	var plain_ctx := _context(t, hostiles)
	var plain := _two_target_snapshot(plain_tactics, plain_ctx, hostiles)
	var fast_tactics := _tactics()
	var fast_ctx := _context(t, hostiles)
	fast_ctx["tactics_cache"] = {}
	var fast := _two_target_snapshot(fast_tactics, fast_ctx, hostiles)
	t.check(fast == plain, "the two-target groups, options and order equal the plain scan")
	t.check(
		_rings_match_combat_spots(fast_tactics, fast_ctx, hostiles)
			and _rings_match_combat_spots(plain_tactics, plain_ctx, hostiles),
		"each self ring, cached or not, equals the unchanged `combat_spots` in content and order",
	)
	t.check(
		(fast_ctx["tactics_cache"]["self_rings"] as Dictionary).size() == 2,
		"the two self rings are cast once and shared by both targets, not once per target",
	)
	t.check(
		fast_tactics.route_queries < plain_tactics.route_queries,
		"shared routes from the NPC are reused (%d vs %d)"
			% [fast_tactics.route_queries, plain_tactics.route_queries],
	)
	t.check(
		fast_tactics.cover_queries < plain_tactics.cover_queries,
		"repeated point/hostile cover is reused (%d vs %d)"
			% [fast_tactics.cover_queries, plain_tactics.cover_queries],
	)
	await _completed_snapshots(t)


## Two whole snapshots of the invader's moment, one with the per-snapshot geometry reuse and one
## with none, each completed: the options (groups, per hostile too), facts and sections (global
## and per hostile) are equal, and so is the order the groups and hostiles come in.
func _completed_snapshots(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 1, 1)
	await t.frames(3)
	var brain := t.controller(&"i", &"debug_state")
	var seen := func() -> bool: return (
		(brain.debug_state().get("contacts", []) as Array).filter(
			func(c): return c.get("hostile", false)
		).size() >= 2
	)
	if not t.require(await t.until(seen, 3.0), "set-up: the invader sees two hostiles"):
		return
	var perception: Node = brain.get("_perception")
	var fast: Dictionary = perception.sense(brain.get("goal"), "", 0)
	var plain: Dictionary = perception.sense(brain.get("goal"), "", 0)
	(plain["demand"].ctx as Dictionary).erase("tactics_cache")
	fast["demand"].complete()
	plain["demand"].complete()
	var per_target: Dictionary = fast["options"]["per_target"]
	t.require(per_target.size() == 2, "set-up: two hostiles are analysed (%d)" % per_target.size())
	t.require(
		(fast["demand"].ctx as Dictionary).has("tactics_cache")
			and not (plain["demand"].ctx as Dictionary).has("tactics_cache"),
		"set-up: one snapshot reuses geometry and the other does not",
	)
	t.expect_eq(fast["options"], plain["options"], "the completed options equal the plain ones")
	t.expect_eq(fast["facts"], plain["facts"], "the facts equal the plain ones")
	t.expect_eq(fast["sections"], plain["sections"], "the sections equal the plain ones")
	t.expect_eq(
		fast["sections_per_target"],
		plain["sections_per_target"],
		"each hostile's sections equal the plain ones",
	)
	t.expect_eq(
		_order(fast), _order(plain), "the groups and the hostiles come in the plain order"
	)


## The order of every dictionary of `snap` that holds groups or hostiles: the option groups, each
## hostile's, the hostiles of the per-target options and sections (a `Dictionary` compares equal
## whatever its key order).
func _order(snap: Dictionary) -> Dictionary:
	var out := {
		"options": (snap["options"] as Dictionary).keys(),
		"per_target": (snap["options"]["per_target"] as Dictionary).keys(),
		"sections": (snap["sections"] as Dictionary).keys(),
		"sections_per_target": (snap["sections_per_target"] as Dictionary).keys(),
	}
	for id in snap["options"]["per_target"]:
		out["groups %s" % id] = (snap["options"]["per_target"][id] as Dictionary).keys()
	for id in snap["sections_per_target"]:
		out["sections %s" % id] = (snap["sections_per_target"][id] as Dictionary).keys()
	return out


## Whether the snapshot ring `_self_combat_spots` equals the standalone `combat_spots` (the
## reference that sorts nearest-first) for each hostile and both ring radii, twice over so the
## second read of a cached ring is covered.
func _rings_match_combat_spots(tactics: RefCounted, ctx: Dictionary, hostiles: Array) -> bool:
	for _pass in 2:
		for target in hostiles:
			var tpos: Vector2 = target["pos"]
			for radius in [tactics.combat_ring_radius, tactics.combat_ring_radius * 2.0]:
				var ex: Array = ctx["exclude"] + tactics.body_rid(target)
				var ring: Dictionary = tactics._self_combat_spots(ctx, tpos, ex, radius)
				var plain: Dictionary = tactics.combat_spots(
					ctx["space"], ctx["self_pos"], tpos, ex, radius
				)
				if ring != plain:
					return false
	return true


## The per-target combat groups one frozen snapshot computes for both hostiles.
func _two_target_snapshot(tactics: RefCounted, ctx: Dictionary, hostiles: Array) -> Dictionary:
	var out := {}
	for target in hostiles:
		var front: float = ctx["fronts"][target["id"]]
		out[target["id"]] = {
			"fire": tactics.fire_positions(ctx, target),
			"flanks": tactics.flank_sides(ctx, target, front),
			"advance": tactics.advance_positions(ctx, target),
		}
	return out


## A district-like frozen context: two known hostiles, their fronts and the NPC's planning map.
func _context(t: TestContext, hostiles: Array) -> Dictionary:
	var npc := t.actor(&"npc")
	var fronts := {}
	for h in hostiles:
		fronts[h["id"]] = (npc.global_position - (h["pos"] as Vector2)).angle()
	return {
		"space": npc.get_world_2d().direct_space_state,
		"map": npc.get_world_2d().navigation_map,
		"self_pos": npc.global_position,
		"exclude": [npc.get_rid()],
		"hostiles": hostiles,
		"allies": [],
		"callouts": [],
		"fronts": fronts,
		"covered_from": {},
	}


## Tuning representative of a combat snapshot, shared by the cached and plain computations.
func _tactics() -> RefCounted:
	var tactics := AgentTactics.new()
	tactics.vision = AgentVision.new()
	tactics.cover_min = 40.0
	tactics.flank_distance = 120.0
	tactics.flank_arc = 30.0
	tactics.flank_ally_radius = 80.0
	tactics.shoot_range = 400.0
	tactics.combat_ring_radius = 96.0
	tactics.combat_ring_count = 12
	tactics.still_speed = 10.0
	tactics.route_clearance = 40.0
	tactics.watch_arc = 90.0
	tactics.fire_spot_distances = [160.0, 260.0]
	return tactics


## A known hostile contact in the shape the tactics geometry reads.
func _contact(npc: Node) -> Dictionary:
	return {
		"id": npc.get_instance_id(), "name": npc.name, "pos": npc.global_position,
		"node": npc, "facing": Vector2.ZERO, "vel": Vector2.ZERO,
	}
