extends RefCounted
## Shared helpers for the grenade tests (not a test itself):
## `const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")`. Reading an NPC (`offered`,
## `callouts`, `grenades`, `wait_act`, `acts`) and setting a scene round a grenade (`hostile`,
## `place`), with the lines a blast is judged on (`character_rids`, `line_clear`, `safe_from_frag`,
## `shielded`, G7). The bus and the spec's constants are `grenade_probe.gd`'s, read there.

const Probe := preload("res://tests/_ai/grenade_probe.gd")


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
