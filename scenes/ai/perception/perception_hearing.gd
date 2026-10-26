extends RefCounted
## AI PERCEPTION sub-domain — the perception's hearing, its part `hearing`: what the NPC hears and
## is told, folded into its memory — hits on and near it and gunfire farther off, where the shots at
## it came from (`shot_from`), footsteps through walls (`docs/hearing.md` H1) and the allies' radio
## callouts — and the reads of it: the shots' rooms, why a room is suspect (G18), the live callouts
## and the heard points the debug overlays draw. Built once with its `AgentPerception`, it holds it
## (a node, so no reference cycle) for the body, the memory and its sibling parts.

const AgentGrenades := preload("res://scenes/ai/perception/agent_grenades.gd")
const AgentSuspicion := preload("res://scenes/ai/perception/agent_suspicion.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")

## The perception it belongs to.
var perception: Node
## Why a room is suspect (G18); see agent_suspicion.gd.
var suspicion: RefCounted


func _init(npc_perception: Node) -> void:
	perception = npc_perception


## Classify one world `&"hit"` event (interface 10) against this NPC and fold it into memory. A hit
## ON the NPC, or any hit within `tuning.combat.hit_awareness_radius` of it, counts as being
## attacked: the incoming direction (and whether it actually hit) is remembered (`under_fire`), the
## engagement is refreshed (`engaged`), and the attacker is handed to the hostility rules. A hit
## farther off but within `tuning.senses.hearing_radius` is gunfire heard (`heard_gunfire`) — an
## investigation lead — but ONLY from a shooter the NPC doesn't already know is hostile: gunfire
## from a character it is fighting (or any other known hostile) is no mystery, already covered by
## COMBAT or that contact's last-seen lead, so it is not a lead to chase. The NPC's own hits are
## ignored, and so is an ally's round striking near it (a teammate's fire is not fire at it; one
## that hits it still is). Returns true when it was a relevant attack, so the controller can kick
## off a fight.
func process_hit(data: Dictionary) -> bool:
	var attacker = data.get("attacker")
	if attacker == perception._character:
		return false  # Our own shot or punch.
	var self_pos: Vector2 = perception._character.global_position
	var pos: Vector2 = data.get("position", self_pos)
	var from: Vector2 = -(data.get("direction", Vector2.RIGHT) as Vector2)
	var hit_me: bool = data.get("victim") == perception._character
	var by_ally: bool = (attacker is Node
			and is_instance_valid(attacker)
			and perception.contacts.hostility.is_ally(attacker.get("faction")
					if attacker.get("faction") != null
					else &""))
	if (not hit_me
			and by_ally
			and self_pos.distance_to(pos) <= perception.tuning.combat.hit_awareness_radius):
		return false  # A teammate's round striking close by: it knows who fired.
	if not hit_me and self_pos.distance_to(pos) > perception.tuning.combat.hit_awareness_radius:
		var known_shooter: bool = attacker is Node and is_instance_valid(attacker) \
			and perception.contacts.hostility.is_hostile(
				attacker.get_instance_id(),
				perception._memory,
			)
		if (self_pos.distance_to(pos) <= perception.tuning.senses.hearing_radius
				and not known_shooter):
			var cell := "%d,%d" % [floori(pos.x / 200.0), floori(pos.y / 200.0)]
			perception._memory.remember(
				&"heard_gunfire",
				{ "pos": pos },
				perception.tuning.memory.lead_ttl,
				cell,
			)
		return false
	perception._memory.remember(
		&"under_fire",
		{ "from": from, "hit": hit_me },
		perception.tuning.combat.under_fire_time,
		"latest",
	)
	perception._memory.remember(&"engaged", {}, perception.tuning.combat.engage_dwell, "latest")
	if not by_ally:
		_note_shot_from(pos, from)
	if attacker is Node and is_instance_valid(attacker):
		perception.contacts.hostility.on_attacked(attacker, perception._memory)
	return true


## Remember where a shot at the NPC came from (`shot_from`, docs/grenades.md G18): the line back
## from where it landed (`at`), along `from`, to the first wall it meets
## (`tuning.senses.hearing_radius` at most). A shot that came in through a doorway runs back into
## the room behind it, so that room is where the shooter is. Kept `tuning.memory.lead_ttl`, long
## after being under fire is over (`tuning.combat.under_fire_time`), keyed by where the line ends so
## shots from two places are two memories.
func _note_shot_from(at: Vector2, from: Vector2) -> void:
	var dir := from.normalized()
	if dir == Vector2.ZERO:
		return
	var far: Vector2 = at + dir * perception.tuning.senses.hearing_radius
	var hit: Dictionary = perception._vision.wall_hit(
		perception._character.get_world_2d().direct_space_state, at, far
	)
	var end: Vector2 = (hit["position"] as Vector2) - dir * 4.0 if not hit.is_empty() else far
	var cell := "%d,%d" % [floori(end.x / 200.0), floori(end.y / 200.0)]
	perception._memory.remember(
		&"shot_from",
		{ "at": at, "pos": end, "from": from },
		perception.tuning.memory.lead_ttl,
		cell,
	)


## Hear one `&"footfall"` (interface 10, `{ position, character, running, crouched }`) through
## walls: the step of a character not of the NPC's own faction (its faction is how it knows its own
## team's steps) within earshot for its gait, `tuning.senses.hear_run` running,
## `tuning.senses.hear_crouch` crouched, else `tuning.senses.hear_walk`, is remembered as
## `heard_footsteps` (`{ pos }`, keyed per walker, so the latest step stands for it;
## `tuning.memory.lead_ttl`): an investigation lead and a reason to suspect the room it came from
## (docs/hearing.md H1). A character it sees right now is no news. The controller drops every
## footfall while the NPC is deaf (G15).
func process_footfall(data: Dictionary) -> void:
	var walker = data.get("character")
	if walker == perception._character or not walker is Node or not is_instance_valid(walker):
		return
	var pos: Vector2 = data.get("position", Vector2.INF)
	var reach: float = perception.tuning.senses.hear_walk
	if data.get("crouched", false):
		reach = perception.tuning.senses.hear_crouch
	elif data.get("running", false):
		reach = perception.tuning.senses.hear_run
	if perception._character.global_position.distance_to(pos) > reach:
		return
	var f = walker.get("faction")
	if (perception.contacts.hostility.is_ally(f if f != null else &"")
			or perception._visible_now.has(walker.get_instance_id())):
		return
	perception._memory.remember(
		&"heard_footsteps",
		{ "pos": pos },
		perception.tuning.memory.lead_ttl,
		str(walker.get_instance_id()),
	)


## The farthest any footfall is heard (px), so the controller can drop the rest before queuing them.
func footfall_reach() -> float:
	return maxf(
		perception.tuning.senses.hear_walk,
		maxf(perception.tuning.senses.hear_run, perception.tuning.senses.hear_crouch),
	)


## Fold one ally radio `&"callout"` (interface 10) into memory: what an ally says it is doing — its
## tactic, target and destination, or its step through a doorway. Ignores its own, non-allies, dead
## speakers, and anything beyond `tuning.radio.callout_range` (<= 0 = unlimited). Each speaker's
## latest callout supersedes its earlier one. An ally that radios a room clear (`cleared_room`)
## teaches this NPC the room and marks it searched, so the team does not clear it twice.
func process_callout(data: Dictionary) -> void:
	var speaker = data.get("speaker")
	if (speaker == perception._character
			or not speaker is Node
			or not is_instance_valid(speaker)
			or speaker.get("is_dead") == true):
		return
	if not perception.contacts.hostility.is_ally(data.get("faction", &"")):
		return
	var at: Vector2 = data.get("position", perception._character.global_position)
	if (perception.tuning.radio.callout_range > 0.0
			and perception._character.global_position.distance_to(at)
					> perception.tuning.radio.callout_range):
		return
	perception.entry.ledger.hear(data, perception._character.global_position)
	if AgentGrenades.is_call(data.get("status")):
		# "Grenade!": a live grenade, not what the ally is doing, so not a callout to weigh.
		perception.grenades.live.called(data)
		return
	if StackClaim.keeps_claim(data):
		# Nor is how an ally's order goes (LD7), its squad's to hear: it leaves what the ally last
		# said it is doing standing.
		return
	perception._memory.remember(
		&"heard_callout",
		data,
		perception.tuning.radio.callout_ttl,
		str(speaker.get_instance_id()),
	)
	var cleared := str(StackClaim.decode(data).get("cleared_room", ""))
	if cleared != "":
		perception._learn_room({ "key": cleared })
		perception._memory.remember(
			&"visited_room",
			{ "key": cleared },
			perception.tuning.memory.search_ttl,
			cleared,
		)
		perception.entry.mark_cleared(cleared)


## Whether room `key` is one the shots at the NPC came from: the line back from a shot at it
## (`shot_from`, kept `tuning.memory.lead_ttl`) runs through it. The behaviour's entry guard reads
## it (`docs/tactical-entry.md` E9: under fire, a walk into the room the shots came from still goes
## by entry).
func shots_from_room(key: String) -> bool:
	for shot in perception._memory.recall_all(&"shot_from"):
		if AgentSuspicion.shot_rooms(perception._rooms, shot).has(key):
			return true
	return false


## Why the NPC suspects a hostile is waiting in room `key` (`docs/grenades.md` G18): its reasons,
## `AgentSuspicion.ORDER`'s ids (gunfire or footsteps heard there, shot at from it, an ally's fight
## in it, a hostile lost in it, by its doorway or heading in), empty when none. What a quiet entry
## reads to turn into a bang when a new one comes up (`docs/tactical-entry.md` E17).
func room_suspicion(key: String) -> Array:
	return suspicion.rooms_suspected(
		perception._rooms, perception.contacts.lost_hostiles(), callouts()
	).get(key, [])


## Debug read: the points of memory topic `topic` (gunfire or footsteps heard), each `{ pos, age }`,
## newest first.
func heard_points(topic: StringName) -> Array:
	var out: Array = []
	for rec in perception._memory.recall_aged(topic):
		out.append({ "pos": rec["data"].get("pos", Vector2.ZERO), "age": rec["age"] })
	return out


## Live ally callouts heard (latest per speaker), with `age`, `name` and the speaker's `id`.
func callouts() -> Array:
	var out: Array = []
	for rec in perception._memory.recall_aged(&"heard_callout"):
		var speaker = rec["data"].get("speaker")
		if not is_instance_valid(speaker) or (speaker as Node).get("is_dead") == true:
			continue
		var c: Dictionary = rec["data"].duplicate()
		c["age"] = rec["age"]
		c["id"] = speaker.get_instance_id()
		c["name"] = str(speaker.name)
		out.append(c)
	return out
