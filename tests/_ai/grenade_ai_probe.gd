extends RefCounted
## Shared helpers for the grenade tests (not a test itself):
## `const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")`. Reading an NPC (`offered`,
## `callouts`, `grenades`, `wait_act`, `acts`, `known_contact`, `watch_until_thrown`) and checking
## it (`check_held_at_old_spot`, `check_sees_again`, `check_thrown_from_outside`), setting a scene
## round a grenade (`hostile`, `place`), the lines a blast is judged on (`character_rids`,
## `line_clear`, `safe_from_frag`, `shielded`, G7) and the plain escape search the evade plan is
## held to (`plain_escape`, with the `escape_threat` and `escape_runner` it takes). The bus and the
## spec's constants are `grenade_probe.gd`'s, read there.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
## The flank maps, whose kitchen `watch_until_thrown` tells fighting outside by.
const Maps := preload("res://tests/_ai/flank_maps.gd")
## The NPC's grenade geometry, whose escape `plain_escape` works out the plain way.
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")


## The tactic level's offered option ids of the NPC `brain` (the controller) from its last decision
## walk: the last `combat` level (the first one picks the hostile).
static func offered(brain: Node) -> Array:
	var found: Array = []
	for l in brain.debug_state().get("decision", {}).get("levels", []):
		if l["node"] == "combat":
			found = (l.get("offered", {}) as Dictionary).keys()
	return found


## The callouts (EventBus `callout`) with `status`, optionally only those spoken by actor `who`.
static func callouts(t: TestContext, status: StringName, who: StringName = &"") -> Array:
	var speaker := t.actor(who) if who != &"" else null
	return Probe.raw(t, &"callout", func(d: Dictionary) -> bool:
		return d.get("status") == status and (speaker == null or d.get("speaker") == speaker))


## What the NPC's grenade awareness reports (`GoalController.debug_grenades()`: `known`, `escape`,
## `throw`); {} while it does not exist.
static func grenades(brain: Node) -> Dictionary:
	return brain.call("debug_grenades") if brain.has_method("debug_grenades") else {}


## The rids of every character (the `characters` group, interface 7), for a ray that looks past
## bodies.
static func character_rids(t: TestContext) -> Array:
	var rids: Array = []
	for c: Node in t.world.get_tree().get_nodes_in_group(&"characters"):
		rids.append((c as CollisionObject2D).get_rid())
	return rids


## True when nothing solid (a wall or a tall piece, not a character) lies on the straight line from
## `a` to `b`.
static func line_clear(t: TestContext, a: Vector2, b: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(a, b, PhysicsLayers.SOLID)
	query.exclude = character_rids(t)
	return t.world.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## An unkillable household puppet standing at `pos` looking at `look_at`: the hostile of a scene (it
## never shoots).
static func hostile(
	s: TestSetup,
	id: StringName,
	pos: Vector2,
	look_at: Vector2,
	props: Dictionary = {},
) -> void:
	var p := {
		"faction": &"household",
		"max_health": 1_000_000.0,
		"movement:aim_point": look_at,
		"facing": (look_at - pos).normalized(),
	}
	p.merge(props, true)
	s.actor(id, &"puppet", pos, p)


## Stand puppet `who` at `at`, facing `look`: a victim set up around a grenade that has come to
## rest, so its distance and facing are known exactly whatever the throw's scatter was.
static func place(t: TestContext, who: StringName, at: Vector2, look: Vector2) -> void:
	var c := t.actor(who)
	c.global_position = at
	c.velocity = Vector2.ZERO
	t.puppet(who).aim_at(look)


## Whether `p` is out of harm from a frag that went off at `burst`: behind a wall or tall piece from
## it, or past its blast radius.
static func safe_from_frag(t: TestContext, burst: Vector2, p: Vector2) -> bool:
	return p.distance_to(burst) >= Probe.BLAST_RADIUS or not line_clear(t, burst, p)


## Wait (sim seconds) until actor `who`'s brain is carrying out an order whose path contains
## `needle` (a decision-tree id such as `grenade` or `stun_entry`); true as soon as it is. `seen`
## (an Array) collects every distinct act that was current, for messages.
static func wait_act(
	t: TestContext,
	who: StringName,
	needle: String,
	timeout: float,
	seen: Array = [],
) -> bool:
	var brain := t.controller(who, &"current_act")
	return await t.until(func() -> bool:
		var act := str(brain.current_act())
		if not seen.has(act):
			seen.append(act)
		return act.contains(needle), timeout)


## The act path (`current_act()`) of actor `who`'s brain right now, for messages.
static func acts(t: TestContext, who: StringName) -> String:
	return str(t.controller(who, &"current_act").current_act())


## G7 cover: whether something between a blast at `burst` and character `c` shields it: a wall, or a
## piece of furniture whose `coverage` is above the character's own (its posture's: crouched 35,
## standing 60), on the straight line from the blast to its body.
static func shielded(t: TestContext, burst: Vector2, c: Node2D) -> bool:
	var height := float(c.get_surface().get("coverage", 60.0))
	var exclude := character_rids(t)
	var space := t.world.get_world_2d().direct_space_state
	for i in 8:
		var query := PhysicsRayQueryParameters2D.create(
			burst, c.global_position, PhysicsLayers.SOLID,
		)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit["collider"]
		var cover := (float(collider.get_surface().get("coverage", 100.0))
				if collider.has_method("get_surface")
				else 100.0)
		if cover > height:
			return true
		exclude.append(hit["rid"])
	return false


## NPC `brain`'s contact for character `p` (the defender's remembered position of the invader),
## from its contacts: `{ pos, visible }`, or {} when it knows none.
static func known_contact(brain: Node, p: Node) -> Dictionary:
	for c in brain.known_contacts_for_display():
		if c.get("node") == p:
			return c
	return {}


## Check that the invader (actor `p`) walked across the defender's front, and the defender still
## holds it at the spot it last saw it, unseen.
static func check_held_at_old_spot(t: TestContext, brain: Node, p: Node, seen_at: Vector2) -> void:
	t.check(t.puppet(&"p").has_arrived(), "the invader walked across the defender's front")
	var known := known_contact(brain, p)
	t.check(
		not known.is_empty() and (known["pos"] as Vector2).distance_to(seen_at) < 60.0,
		"the defender still holds the invader at the spot it last saw it (%s, now at %s)"
			% [str(known.get("pos")), str(p.global_position.round())],
	)
	t.check(not known.is_empty() and not bool(known.get("visible", true)), "and does not see it")


## Watch actor `i` (`inv`, the invader) until a grenade is thrown (at most 60 s): `seen` (each act
## it took), `offered` (its tactic level offered `grenade`) and `fighting_outside` (it fought
## `target` from outside `Maps.HOUSE_KITCHEN`).
static func watch_until_thrown(t: TestContext, inv: Node, target: String) -> Dictionary:
	var brain := t.controller(&"i", &"current_act")
	var seen: Array = []
	var was_offered := [false]
	var fighting_outside := [false]
	var watch := func() -> bool:
		var act := acts(t, &"i")
		if not seen.has(act):
			seen.append(act)
		if (act.begins_with("combat/%s" % target)
				and not Maps.HOUSE_KITCHEN.has_point(inv.global_position)):
			fighting_outside[0] = true
		if offered(brain).has("grenade"):
			was_offered[0] = true
		return t.happened(&"throw")
	await t.until(watch, 60.0)
	return { "seen": seen, "offered": was_offered[0], "fighting_outside": fighting_outside[0] }


## Check that the invader (`inv`) threw its frag (`seen`, the acts it took, for the message),
## from outside `Maps.HOUSE_KITCHEN`; false when it threw none.
static func check_thrown_from_outside(t: TestContext, inv: Node, seen: Array) -> bool:
	var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == inv)
	if not t.check(
			not throws.is_empty() and throws[0]["data"].get("kind") == &"frag",
			"the invader threw its frag (acts %s)" % str(seen),
	):
		return false
	t.check(
		not Maps.HOUSE_KITCHEN.has_point(throws[0]["data"]["position"]),
		"from outside the kitchen (thrown at %s)"
			% str((throws[0]["data"]["position"] as Vector2).round()),
	)
	return true


## Check that the blindness is over (defender `brain`, invader `p`): it sees the invader again,
## where it is now.
static func check_sees_again(t: TestContext, brain: Node, p: Node) -> void:
	var sees_where_it_is := func() -> bool:
		var known := known_contact(brain, p)
		return (
			bool(known.get("visible", false))
				and (known["pos"] as Vector2).distance_to(p.global_position) < 40.0
		)
	t.check(
		await t.until(sees_where_it_is, 4.0),
		"once it can see it re-reads the invader where it stands (acting: %s)"
			% str(brain.current_act()),
	)


## `AgentThrow.escape` with nothing shared: every candidate snapped, judged and routed, as
## `ai/grenade/escape_spot_matches_plain` pins it. `search` is the search's world (`space`, `map`,
## `exclude`).
static func plain_escape(
		g: AgentThrow,
		search: Dictionary,
		threat: GrenadeThreat,
		runner: GrenadeRunner,
) -> Dictionary:
	var spots := _plain_spots(g, search, threat, runner.from)
	var allowed := maxf(threat.fuse_left - AgentThrow.ARRIVE_MARGIN, 0.0) * runner.speed
	return _plain_best(search["map"], spots, runner.from, allowed)


## The grenade as the escape takes it.
static func escape_threat(
	kind: StringName,
	radius: float,
	burst: Vector2,
	fuse: float,
) -> GrenadeThreat:
	var grenade := GrenadeThreat.new()
	grenade.kind = kind
	grenade.radius = radius
	grenade.burst = burst
	grenade.fuse_left = fuse
	return grenade


## The runner as the escape takes it.
static func escape_runner(from: Vector2, speed: float) -> GrenadeRunner:
	var body := GrenadeRunner.new()
	body.from = from
	body.speed = speed
	return body


## Every candidate of the plain search snapped and judged: `{ spot, crouch }` for each that lands
## out of the burst's zone or shielded from it, `crouch` when only a crouched body is shielded.
static func _plain_spots(
		g: AgentThrow,
		search: Dictionary,
		threat: GrenadeThreat,
		from: Vector2,
) -> Array:
	var map: RID = search["map"]
	var zone := {
		"burst": threat.burst,
		"out_r": g._zone_radius(threat.kind, threat.radius) + AgentThrow.OUTSIDE_SLACK,
		"reach": g.cover_reach(threat.kind),
	}
	var spots: Array = []
	# The candidates' grenade as the plain search builds it: its kind, radius and burst.
	var around := GrenadeThreat.new()
	around.kind = threat.kind
	around.radius = threat.radius
	around.burst = threat.burst
	for p in g._candidates(search["space"], around, from, search["exclude"]):
		var q := NavBuilder.snap(map, p)
		if q.distance_to(p) > AgentThrow.SNAP_TOLERANCE:
			continue
		var spot := _plain_spot(g, search, q, zone)
		if not spot.is_empty():
			spots.append(spot)
	return spots


## The plain search's verdict on the snapped candidate `q` for the burst `zone` (`burst`, `out_r`,
## `reach`): `{ spot, crouch }`, `crouch` when only a crouched body is shielded there; `{}` when it
## is inside the zone and shielded neither way.
static func _plain_spot(
	g: AgentThrow,
	search: Dictionary,
	q: Vector2,
	zone: Dictionary,
) -> Dictionary:
	var space: PhysicsDirectSpaceState2D = search["space"]
	var exclude: Array = search["exclude"]
	var burst: Vector2 = zone["burst"]
	var reach: float = zone["reach"]
	var crouch := false
	if (q.distance_to(burst) < zone["out_r"]
			and not g._covered(
				space,
				burst,
				q,
				AgentThrow._cover_rule(g.stand_height(), exclude, reach),
			)):
		if not g._covered(
			space,
			burst,
			q,
			AgentThrow._cover_rule(g.crouch_height(), exclude, reach),
		):
			return {}
		crouch = true
	return { "spot": q, "crouch": crouch }


## Of `spots`, the one with the shortest route from `from` within `allowed` px:
## `{ spot, crouch, route }`, `spot` INF when none is in time.
static func _plain_best(map: RID, spots: Array, from: Vector2, allowed: float) -> Dictionary:
	var best := { "spot": Vector2.INF, "crouch": false, "route": INF }
	for s: Dictionary in spots:
		var length := NavBuilder.path_length(NavBuilder.route(map, from, s["spot"]))
		if length <= allowed and length < best["route"]:
			best = { "spot": s["spot"], "crouch": s["crouch"], "route": length }
	return best
