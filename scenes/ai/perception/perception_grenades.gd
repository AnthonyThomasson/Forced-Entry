extends RefCounted
## AI PERCEPTION sub-domain — the perception's grenades, its part `grenades`: the grenade geometry
## (agent_throw.gd, `throw`) and the live grenades known with the plan to get clear of them
## (agent_grenades.gd, `live`), which it holds, the grenades the NPC carries, the latest burst
## (`last_burst`) and the flash a stun its side threw left on the hostiles it knew (G15, G16), and
## the reads the behaviour sub-domain makes of them (the lob, the reach, the fuse, the danger zone).
## Built once with its `AgentPerception`, it holds it (a node, so no reference cycle) for the body,
## the memory and its sibling parts.

const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
## The share of a stun's longest blindness (`max_blind`) a hostile caught at its burst is taken to
## be blinded for, at point-blank (less with distance): the NPC cannot see which way their eyes were
## turned.
const FLASH_SHARE := 0.8

## The perception it belongs to.
var perception: Node
## The grenade geometry (danger zone, escape spot, lob); see agent_throw.gd.
var throw: RefCounted
## The live grenades known and the plan to get clear of them; see agent_grenades.gd.
var live: RefCounted
## The latest grenade burst (`{ kind, position, frame, team }`: the game-clock frame
## (`GameClock.frame()`) it was taken note of in, and whether the NPC or an ally threw it), or {}: a
## bang entry waits for its stun's, and an entry goes in on its own team's burst in the room (E17).
var last_burst := {}


func _init(npc_perception: Node) -> void:
	perception = npc_perception


## How many grenades of `kind` `character` carries (`Character.inventory.item_count`).
static func count(character: Node, kind: StringName) -> int:
	return int(character.inventory.item_count(AgentThrow.SLOTS[kind]))


## The kinds `character` carries, a frag first: `[&"frag", &"stun"]` less those it has none of.
static func carried(character: Node) -> Array:
	return AgentThrow.SLOTS.keys().filter(func(k): return count(character, k) > 0)


## A grenade came down (`&"grenade"`, `{ position, kind, stage }`): heard if within earshot and the
## NPC is not `deaf`, so known (G16).
func process(data: Dictionary, deaf: bool) -> void:
	live.hear(data, deaf)


## A grenade went off (`&"explosion"`, `{ position, kind, attacker, ... }`): it is forgotten, and so
## is the plan to get clear of it. A stun the NPC or an ally threw also blinds the hostiles it knew
## in its flash (`flashed`).
func process_explosion(data: Dictionary) -> void:
	live.burst(data.get("position", Vector2.INF), data.get("kind", &""))
	var by = data.get("attacker")
	var team: bool = (by == perception._character
			or (by is Node and is_instance_valid(by) and _is_ally_body(by)))
	last_burst = {
		"kind": data.get("kind", &""),
		"position": data.get("position", Vector2.INF),
		"frame": GameClock.frame(),
		"team": team,
	}
	if data.get("kind") == &"stun":
		_note_flash(data)


## Whether `by`, a live body, is of the NPC's side (its `faction`, none read as `&""`).
func _is_ally_body(by: Object) -> bool:
	return perception.contacts.hostility.is_ally(
		by.get("faction") if by.get("faction") != null else &""
	)


## A stun thrown by the NPC or an ally went off at `data.position`: every hostile it knew of within
## the flash radius with a clear line from the burst is blinded for a few seconds (`FLASH_SHARE` of
## the stun's longest blindness at the burst, less with distance), which it holds as `flashed` (the
## contact's `blind`). It cannot see their eyes, but it knows what it threw the flash at.
func _note_flash(data: Dictionary) -> void:
	var by = data.get("attacker")
	if by != perception._character and not (is_instance_valid(by) and _is_ally_body(by)):
		return
	var burst: Vector2 = data["position"]
	var space: PhysicsDirectSpaceState2D = perception._character.get_world_2d().direct_space_state
	var rids := character_rids()
	var flash := float(data.get("radius", 0.0))  # (The flash radius the burst reports.)
	var cover := CoverRule.new()
	cover.height = throw.stand_height()
	cover.exclude = rids
	cover.cover_reach = throw.cover_reach(&"stun")
	for c in perception.contacts.sightings(null, perception.tuning.memory.lead_ttl, -1.0, true):
		var d: float = burst.distance_to(c["pos"])
		if d > flash:
			continue
		if throw.shielded(space, burst, c["pos"], cover):
			continue
		perception._memory.remember(
			&"flashed",
			{ "id": c["id"] },
			maxf(throw.max_blind_of(&"stun") * FLASH_SHARE * (1.0 - d / flash), 1.0),
			str(c["id"]),
		)


## The live grenades the NPC knows of (seen, heard, called or its own), soonest to go off first, as
## `{ point, kind, fuse_left, fuse, radius, source }` (`source`: `&"seen"` / `&"heard"` /
## `&"called"` / `&"own"`).
func known() -> Array:
	return live.known()


## The plan to get clear of the live grenade that goes off first among those the NPC is in the
## danger zone of (or is already running from): `{ id, point, kind, radius, spot, crouch, fuse_left,
## landed, lies }` (see agent_grenades.gd `plan`), or {}. Made from where the NPC stands and kept
## while the grenade lives. A pure read of what it knows plus the physics space and the navmesh.
func evade_plan() -> Dictionary:
	if not live.has_known():
		return {}
	return live.plan(
		perception._character.get_world_2d().direct_space_state,
		perception._character.get_world_2d().navigation_map,
		character_rids(),
	)


## The grenades to radio now, `{ point, kind }`, each once, when they have come down (see
## agent_grenades.gd `announcements`).
func announcements() -> Array:
	return live.announcements()


## Whether a thrower standing at `at` can lob a grenade of `kind` onto `to`: within its throw range,
## and the lob from its hand is clear of everything between, low furniture included (agent_throw.gd
## `can_lob`). `walked`: the thrower walks to `at` first, so the lob must be clear wherever that
## walk may end (`throw_clear_on_arrival`).
func can_lob(at: Vector2, to: Vector2, kind: StringName, walked := false) -> bool:
	var space: PhysicsDirectSpaceState2D = perception._character.get_world_2d().direct_space_state
	var rids: Array = character_rids()
	if not walked:
		return throw.can_lob(space, at, to, throw.range_of(kind), rids)
	return (at.distance_to(to) <= throw.range_of(kind)
			and throw.throw_clear_on_arrival(space, at, to, rids))


## Whether the lob a thrower standing at `at` throws onto `to` flies clear, from its hand (any
## distance: the range is `AgentThrow.range_of`'s).
func throw_clear(at: Vector2, to: Vector2) -> bool:
	return throw.throw_clear(
		perception._character.get_world_2d().direct_space_state,
		at,
		to,
		character_rids(),
	)


## How far (px) from its spot a thrower stands to let a grenade of `kind` go: its range less a few
## px, so one that drifted a step past it closes in first (agent_throw.gd `reach_of`).
func reach(kind: StringName) -> float:
	return throw.reach_of(kind)


## Seconds from release to the burst of a grenade of `kind` (what the NPC learned of it off the
## grenades it carries).
func fuse(kind: StringName) -> float:
	return throw.fuse_of(kind)


## Whether a standing body at `p` is inside the danger zone of a grenade of `kind` bursting at
## `burst`: within its reach (a frag's blast radius and the evade margin, a stun's flash radius) and
## not shielded from the burst by a wall or taller furniture (agent_throw.gd `in_zone`; bodies
## shield nothing). False for a kind the NPC has never met.
func in_zone(kind: StringName, burst: Vector2, p: Vector2) -> bool:
	var threat := GrenadeThreat.new()
	threat.kind = kind
	threat.radius = throw.radius_of(kind)
	threat.burst = burst
	return throw.in_zone(
		perception._character.get_world_2d().direct_space_state, threat, p, throw.stand_height(),
		character_rids(),
	)


## The rids of every character in the world, this NPC included: the bodies a blast or a lob goes
## through.
func character_rids() -> Array:
	var rids := [perception._character.get_rid()]
	for other in perception._other_characters():
		if other is CollisionObject2D:
			rids.append(other.get_rid())
	return rids
