extends RefCounted
## AI domain · TEAM — the defenders' ambush rule, a part the squad builds once and holds as
## `ambush`: an AI leader orders its crew to ambush the doorway into its room an attack comes
## through, before contact when it can. On a callout from its side (the leader's own included) it
## reads a threat point: a COMBAT callout's `target_pos` (the hostile's last-known spot, else where
## the shots came from) or an INVESTIGATE callout's `lead_pos` (the freshest lead that places a
## hostile); a point in the leader's own room, `Vector2.INF` or a leader in no room orders nothing.
## The doorway is `AttackDoor.doorway` (the last doorway on the shortest way from the point's room
## into the leader's). The order is an `ambush` of that doorway from the leader's room, through
## `Squad.issue` as a human leader's request is, to the living NPC members holding no order, the
## leader included; with three or more of them the last in spawn order (never the leader) is left
## out, the rear guard, which follows as any member with no order does. A re-order needs a new
## doorway, `SquadAmbushConfig.reorder_gap` s since the last order and at least
## `SquadAmbushConfig.min_recipients` recipients; the last doorway and the clock move only when an
## order is posted, and start afresh with a new leader (`reset`). It holds its squad (a node, so no
## reference cycle) for the leader and `issue`.

const AttackDoor := preload("res://scenes/ai/team/attack_door.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")

## The squad it belongs to.
var squad: Node
## Whether the squad runs the rule (its roster's `ambush_attacks`: the defenders' side).
var enabled := false
## The house's doorways and rooms (`WorldGen.get_openings` / `get_rooms`).
var _openings: Array = []
var _rooms: Array = []
## The doorway of the last ambush ordered ("" for none since the leader took the lead).
var _door := ""
## When it was ordered (`GameClock.seconds()`).
var _at := 0.0


func _init(team: Node) -> void:
	squad = team


## Run the rule (`on`) over the house's `openings` and `rooms`.
func setup(on: bool, openings: Array, rooms: Array) -> void:
	enabled = on
	_openings = openings
	_rooms = rooms


## A new leader: the last doorway and the cool-down start afresh.
func reset() -> void:
	_door = ""
	_at = 0.0


## Callout `data` from the squad's side, heard while an AI leads: order the ambush of the doorway
## its threat point's attack comes through, to `free` (the living NPC members holding no order, in
## spawn order), when the rule says so.
func hear(data: Dictionary, free: Array) -> void:
	var leader: Node = squad.leader()
	if not enabled or not leader is Node2D:
		return
	var room := HouseRooms.key_at((leader as Node2D).global_position, _rooms)
	var opening := AttackDoor.doorway(threat_point(data), room, _rooms, _openings)
	if opening == "" or opening == _door:
		return
	var again := _door != ""
	if again and GameClock.seconds() - _at < SquadAmbushConfig.reorder_gap:
		return
	var to := _recipients(free, leader)
	if to.is_empty() or (again and to.size() < SquadAmbushConfig.min_recipients):
		return
	var order: Dictionary = squad.issue({
		"kind": "ambush", "to": to, "opening": opening, "room": room,
	})
	if not order.is_empty():
		_door = opening
		_at = GameClock.seconds()


## Where callout `data` places a threat: a COMBAT decision's `target_pos`, an INVESTIGATE decision's
## `lead_pos`; `Vector2.INF` for any other callout (an entry step, an order's progress, a grenade
## call) or one that places nothing.
static func threat_point(data: Dictionary) -> Vector2:
	if str(data.get("entry_step", "")) != "" or StackClaim.keeps_claim(data):
		return Vector2.INF
	var point: Variant = Vector2.INF
	match str(data.get("path", "")).get_slice("/", 0):
		"combat":
			point = data.get("target_pos", Vector2.INF)
		"investigate":
			point = data.get("lead_pos", Vector2.INF)
	return point if point is Vector2 else Vector2.INF


## `free` less the rear guard: with three or more, the last of them that is not `leader`.
static func _recipients(free: Array, leader: Node) -> Array:
	var to := free.duplicate()
	if to.size() < 3:
		return to
	for i in range(to.size() - 1, -1, -1):
		if to[i] != leader:
			to.remove_at(i)
			break
	return to
