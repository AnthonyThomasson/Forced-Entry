extends RefCounted
## Shared helpers for the tests that watch a match's NPCs in a generated house
## (tests/ai/investigate/defenders_stay_in_house_*, `ai/entry/entry_team_no_bumping`,
## `ai/movement/follow_defenders`; not a test itself): `house` declares the house and a match over
## it placed the way Main places one (`s.match`, `MatchBuilder.populate`: the defenders each at a
## clear spot in a random room, the invader team in one group outside the house, out of the views
## of its exterior doorways, heading for its front entrance; everyone armed, styled and in its
## side's squad), `side` reads one side's NPCs off it, and `watch` tells whether a defender ever
## steps outside.

## How far past a room's rectangle (px) a defender may stand before it has left: a doorway's depth.
const SLACK := 30.0


## Declare generated house `seed_value` (`--seed=N` pins another) and a match over it with
## `defenders` defenders and `invaders` invaders, its placement seeded with the house's seed.
static func house(s: TestSetup, seed_value: int, defenders: int, invaders: int) -> void:
	s.house(seed_value)
	s.match({ "defenders": { "count": defenders }, "invaders": { "count": invaders } })


## The match's NPCs of `faction` (`&"household"` the defenders, `&"invader"` the invaders), in
## spawn order.
static func side(t: TestContext, faction: StringName) -> Array:
	return (t.match().get("combatants", []) as Array).filter(
		func(c): return is_instance_valid(c) and c.get("faction") == faction,
	)


## Whether `p` is within the house: inside some room's rectangle, with a doorway's slack.
static func inside(t: TestContext, p: Vector2) -> bool:
	for room in t.rooms:
		if (room["rect"] as Rect2).grow(SLACK).has_point(p):
			return true
	return false


## Watch `defenders` for `seconds`; returns {} when none ever left the house, else what the first to
## leave was doing (`name`, `at`, `t`, `status`, `path`).
static func watch(t: TestContext, defenders: Array, seconds: float) -> Dictionary:
	var elapsed := 0.0
	var history := {}
	while elapsed < seconds:
		await t.seconds(0.1)
		elapsed += 0.1
		for npc in defenders:
			if not is_instance_valid(npc) or npc.get("is_dead"):
				continue
			var brain: Node = TestContext.controller_of(npc)
			var trail: Array = history.get(npc.name, [])
			if trail.is_empty() or elapsed - trail[-1]["t"] >= 0.5:
				var st: Dictionary = brain.debug_state()
				trail.append({
					"t": snappedf(elapsed, 0.1), "at": npc.global_position.round(),
					"act": brain.current_act(), "to": st.get("params", {}).get("point", null),
					"arrived": st.get("arrived"), "prim": st.get("primitive"),
				})
				history[npc.name] = trail.slice(-14)
			if not inside(t, npc.global_position):
				return {
					"name": npc.name, "at": npc.global_position.round(),
					"t": snappedf(elapsed, 0.1), "status": brain.debug_status(),
					"nearest_room": _nearest_room(t, npc.global_position), "levels": _levels(brain),
					"asked": _last_asked(brain), "trail": history[npc.name],
				}
	return {}


## The room whose rectangle is closest to `p`, as "key rect", for a failure message.
static func _nearest_room(t: TestContext, p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for room in t.rooms:
		var rect: Rect2 = room["rect"]
		var d := p.distance_to(Vector2(
			clampf(p.x, rect.position.x, rect.end.x),
			clampf(p.y, rect.position.y, rect.end.y),
		))
		if d < best_d:
			best_d = d
			best = "%s %s (%.0f px away)" % [room["key"], rect, d]
	return best


## The last decision walk's levels as "node: pick (of offered)" lines.
static func _levels(brain: Node) -> Array:
	var out: Array = []
	for l in brain.debug_state().get("decision", {}).get("levels", []):
		out.append("%s: %s of %s%s" % [
			l.get("node"),
			l.get("pick"),
			(l.get("offered", {}) as Dictionary).keys(),
			" (auto)" if l.get("auto", false) else "",
		])
	return out


## What Von was last asked about investigating (state, offered ids, its probabilities and pick), for
## a failure message.
static func _last_asked(brain: Node) -> Dictionary:
	var found := {}
	for l in brain.debug_state().get("decision", {}).get("levels", []):
		if ((l.get("offered", {}) as Dictionary).has("stay")
				or String(l.get("node")) == "investigate"):
			found = {
				"node": l.get("node"),
				"state": l.get("state"),
				"offered": l.get("offered"),
				"pick": l.get("pick"),
				"p": l.get("probabilities"),
			}
	return found
