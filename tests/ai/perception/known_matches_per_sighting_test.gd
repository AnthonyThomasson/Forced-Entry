extends GameTest
## AC7 (#192): known() reads the hostile verdicts and flashed ids once for the whole contact list,
## not once for every sighting. Its answer is held to the plain per-sighting rule over several
## sightings, a newer hostile verdict, flashes, expired events and a freed character. The bulk-read
## counter is the observable that proves the shared lookup, not merely the same answer, was used.

const CONTACT_TTL := 10.0
const SHORT_TTL := 0.1


func describe() -> Dictionary:
	return {
		"name": "Known contacts match with one bulk hostility read",
		"description": "Verdict changes, flashes, expiry and freed characters leave known() "
			+ "equal to the plain rule, while one call reads all hostile verdicts together.",
		"tags": ["ai", "perception", "scripted"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 500))
	s.von_down()
	s.switch(&"ai.hostile_on_sight", false)
	s.actor(&"npc", &"invader", Vector2(100, 250), { "movement:speed": 0.0 })
	s.actor(&"near", &"puppet", Vector2(250, 250), { "faction": &"household" })
	s.actor(&"far", &"puppet", Vector2(700, 250), { "faction": &"household" })
	s.actor(&"gone", &"puppet", Vector2(450, 250), { "faction": &"household" })


func run(t: TestContext) -> void:
	await t.frames(2)
	var brain := t.controller(&"npc", &"debug_state")
	var perception: Node = brain.get("_perception")
	var memory: RefCounted = perception.get("_memory")
	var contacts: RefCounted = perception.contacts
	var near := t.actor(&"near")
	var far := t.actor(&"far")
	var gone := t.actor(&"gone")
	_remember_sighting(memory, near, CONTACT_TTL)
	_remember_sighting(memory, far, CONTACT_TTL)
	_remember_sighting(memory, gone, CONTACT_TTL)
	memory.remember(&"hostile", { "id": far.get_instance_id(), "reason": "seen" }, CONTACT_TTL)
	memory.remember(&"hostile", { "id": near.get_instance_id(), "reason": "seen" }, SHORT_TTL)
	memory.remember(&"flashed", { "id": far.get_instance_id() }, CONTACT_TTL)
	perception.sight.visible_now[near.get_instance_id()] = true
	if not t.require(
			_compare(contacts, perception, memory) == "",
			"the initial contacts match the per-sighting reference",
	):
		return
	var before: Variant = contacts.hostility.get("bulk_reads")
	contacts.known(perception.get("_character").global_position)
	var after: Variant = contacts.hostility.get("bulk_reads")
	t.check(
		after != null and int(after) == (int(before) if before != null else 0) + 1,
		"known() makes one bulk hostility read however many sightings it holds",
	)
	memory.remember(
		&"hostile", { "id": near.get_instance_id(), "reason": "attacked you" }, CONTACT_TTL
	)
	memory.remember(&"flashed", { "id": near.get_instance_id() }, CONTACT_TTL)
	perception.sight.visible_now.clear()
	t.check(
		_compare(contacts, perception, memory) == "",
		"the newest verdict and the flashes match the per-sighting reference",
	)
	gone.queue_free()
	await t.frames(2)
	t.check(
		_compare(contacts, perception, memory) == "",
		"a freed character is dropped exactly as the per-sighting rule drops it",
	)
	await t.seconds(SHORT_TTL + 0.1)
	t.check(
		_compare(contacts, perception, memory) == "",
		"expired verdicts and contacts match the per-sighting reference",
	)


## The plain rule: each live sighting asks hostility for its own freshest verdict and memory for its
## own flash, then the contacts are sorted hostiles first and nearest first.
func _reference(contacts: RefCounted, perception: Node, memory: RefCounted) -> Array:
	var out: Array = []
	for rec: Dictionary in memory.recall_aged(&"saw_character"):
		if rec["age"] > perception.tuning.memory.contact_ttl:
			continue
		var data: Dictionary = rec["data"]
		var node = data.get("node")
		if not is_instance_valid(node) or node.get("is_dead") == true:
			continue
		var contact := data.duplicate()
		contact["age"] = rec["age"]
		contact["reason"] = contacts.hostility.reason(contact["id"], memory)
		contact["hostile"] = contact["reason"] != ""
		contact["visible"] = perception.sight.visible_now.has(contact["id"])
		contact["blind"] = memory.age_of(&"flashed", "id", contact["id"]) < INF
		out.append(contact)
	var self_pos: Vector2 = perception.get("_character").global_position
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["hostile"] != b["hostile"]:
			return a["hostile"]
		return (a["pos"] as Vector2).distance_squared_to(self_pos) \
			< (b["pos"] as Vector2).distance_squared_to(self_pos)
	)
	return out


func _compare(contacts: RefCounted, perception: Node, memory: RefCounted) -> String:
	var self_pos: Vector2 = perception.get("_character").global_position
	var actual: Array = contacts.known(self_pos)
	var expected: Array = _reference(contacts, perception, memory)
	return "" if actual == expected else "known %s, per-sighting %s" % [actual, expected]


func _remember_sighting(memory: RefCounted, character: Node, ttl: float) -> void:
	var id := character.get_instance_id()
	memory.remember(
		&"saw_character",
		{
			"id": id,
			"node": character,
			"name": str(character.name),
			"faction": character.faction,
			"ally": false,
			"pos": character.global_position,
			"vel": Vector2.ZERO,
			"facing": character.facing,
			"wound_dmg": 0.0,
			"inside": false,
			"room_type": "",
			"item": "nothing",
			"reloading": false,
			"posture": &"stand",
		},
		ttl,
		str(id),
	)
