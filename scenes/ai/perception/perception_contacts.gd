extends RefCounted
## AI PERCEPTION sub-domain — the perception's contacts, its part `contacts`: the characters the NPC
## knows of, read off its `saw_character` sightings through the hostility rules (agent_hostility.gd,
## which it holds) — the live contacts, every character seen, the hostiles lost track of — and where
## it last knew a hostile to be. Built once with its `AgentPerception`, it holds it (a node, so no
## reference cycle) for the memory and its sibling parts.

## The perception it belongs to.
var perception: Node
## The hostility rules; see agent_hostility.gd.
var hostility: RefCounted


func _init(npc_perception: Node) -> void:
	perception = npc_perception


## Every character the agent currently knows of (seen within `tuning.memory.contact_ttl`) — the
## latest sighting per character, with `hostile` / `reason`, `visible` (seen on the latest tick) and
## `age`. Hostiles first, then nearest to `self_pos`. Dead or freed characters are dropped.
func known(self_pos: Vector2) -> Array:
	return sightings(self_pos, _contact_ttl())


## Every character in memory regardless of tuning.memory.contact_ttl — all non-expired sightings (up
## to tuning.memory.lead_ttl, typically 20 s). Same dict shape as known() but covers stale sightings
## too, so external observers (e.g. the spectator inspector) can see the NPC's full knowledge
## window.
func all_seen_characters(self_pos: Vector2) -> Array:
	return sightings(self_pos)


## Hostiles the NPC has lost track of — last seen longer ago than `tuning.memory.contact_ttl` but
## within `tuning.memory.lead_ttl` — newest first: where to investigate.
func lost_hostiles() -> Array:
	return sightings(null, INF, _contact_ttl(), true)


## Where the NPC last knew hostile `target_id` to be (its last sighting), else, with nobody known,
## where the shots at it came from (`shot_from`); `Vector2.INF` when it knows neither. What a combat
## callout radios as `target_pos` (interface 10).
func target_pos(target_id: int) -> Vector2:
	if target_id != 0:
		for seen in perception._memory.recall_all(&"saw_character"):
			if seen["id"] == target_id:
				return seen["pos"]
	var shot: Dictionary = perception._memory.recall(&"shot_from")
	return shot.get("pos", Vector2.INF)


## How long (s) a sighting counts as a live contact. A blinded NPC cannot tell that a contact has
## gone, so it keeps acting on every sighting its memory holds (G15); it is back to
## `tuning.memory.contact_ttl` the moment it can see.
func _contact_ttl() -> float:
	return maxf(
		perception.tuning.memory.contact_ttl,
		perception.tuning.memory.lead_ttl,
	) if perception._blind else perception.tuning.memory.contact_ttl


## The live character sightings in memory as contact dicts — the one source behind known(),
## all_seen_characters() and lost_hostiles(). Keeps sightings with age in (`min_age`, `max_age`];
## `hostile_only` drops non-hostiles; dead or freed characters are always dropped. Given a
## `self_pos` (a Vector2) the result is sorted hostiles-first then nearest to it, else it keeps the
## memory's newest-first order.
func sightings(self_pos: Variant, max_age := INF, min_age := -1.0, hostile_only := false) -> Array:
	var out: Array = []
	for rec in perception._memory.recall_aged(&"saw_character"):
		if rec["age"] > max_age or rec["age"] <= min_age:
			continue
		var c := _live_sighting(rec)
		if c.is_empty() or (hostile_only and not c["hostile"]):
			continue
		out.append(c)
	if self_pos is Vector2:
		out.sort_custom(func(a, b):
			if a["hostile"] != b["hostile"]:
				return a["hostile"]
			return ((a["pos"] as Vector2).distance_squared_to(self_pos)
					< (b["pos"] as Vector2).distance_squared_to(self_pos)))
	return out


## A remembered sighting (`{ data, age }`) as a contact dict, or empty when its character is gone.
func _live_sighting(rec: Dictionary) -> Dictionary:
	var data: Dictionary = rec["data"]
	var n = data.get("node")
	if not is_instance_valid(n) or (n as Node).get("is_dead") == true:
		return {}
	var c := data.duplicate()
	c["age"] = rec["age"]
	c["reason"] = hostility.reason(c["id"], perception._memory)
	c["hostile"] = c["reason"] != ""
	c["visible"] = perception._visible_now.has(c["id"])
	c["blind"] = perception._memory.age_of(&"flashed", "id", c["id"]) < INF
	return c
