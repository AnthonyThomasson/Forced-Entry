extends RefCounted
## AI PERCEPTION sub-domain — the perception's orders, its part `orders`: the leader's order the NPC
## holds (`docs/leadership.md` LD5: memory topic `order`, permanent, one per NPC), how it ends
## (done, refused, cancelled), the one that ended for the controller to radio (LD7) and the ambush
## that ends on first contact (LD15, D18). Built once with its `AgentPerception`, it holds it (a
## node, so no reference cycle) for the body, the memory and its sibling parts.

const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const StackMember := preload("res://scenes/ai/perception/stack/stack_member.gd")

## The perception it belongs to.
var perception: Node
## The order that ended done or refused, until the controller radios it (`take_ended`).
var _ended_order := {}


func _init(npc_perception: Node) -> void:
	perception = npc_perception


## Take one `&"order"` (interface 10, `docs/leadership.md` LD5:
## `{ id, leader, faction, to, kind, ... }`) when it names this NPC in `to` and comes from its own
## side: kept as the live order (memory topic `order`, permanent, one per NPC), replacing the one it
## held; a `cancel` ends the one it holds. An order never lapses on a timer: it ends only when it is
## done, cancelled or replaced (`end`). A `go` (LD13) replaces nothing: it releases the held stack
## order the NPC holds at its doorway (`go: true` on the live order, latched: the stack goes once
## ready, however long before that the go came; `go_mode` the mode it names, the one a held rally
## goes in, D31), and asks for no new decision. True when the NPC's
## order changed (the controller then decides at once).
func process(data: Dictionary) -> bool:
	if (not (data.get("to", []) as Array).has(perception._character)
			or not perception.contacts.hostility.is_ally(data.get("faction", &""))):
		return false
	if String(data.get("kind", "")) == "go":
		var live := current()
		if (String(live.get("kind", "")) == "stack"
				and String(live.get("opening", "")) == String(data.get("opening", ""))):
			live = live.duplicate()
			live["go"] = true
			if data.has("mode"):
				live["go_mode"] = String(data["mode"])
			perception._memory.remember(&"order", live, 0.0, "live")
		return false
	if String(data.get("kind", "")) == "cancel":
		var held := current()
		if held.is_empty():
			return false
		end(held["id"], "cancelled")
		return true
	perception._memory.remember(&"order", data.duplicate(), 0.0, "live")
	return true


## The live order (`process`), or {} when the NPC holds none.
func current() -> Dictionary:
	var held: Dictionary = perception._memory.recall(&"order")
	return {} if held.is_empty() or held.has("ended") else held


## The room the stack of the live order is held to enter (LD13, D31): a `stack` order held for its
## leader's go (`wait_go`; a join of the human leader's rally too) whose go has come neither on the
## order (`go`) nor off the radio (`DoorStack.held` over the claims heard at its doorway); ""
## otherwise. A member holding one fights on the stack's side of the doorway (D31).
func held_room() -> String:
	var live := current()
	if (String(live.get("kind", "")) != "stack"
			or not bool(live.get("wait_go", false))
			or bool(live.get("go", false))):
		return ""
	var into := String(live.get("into", ""))
	var join := StackClaim.is_join(live)
	# The NPC as its claims under this order describe it (a join's carry no order id, D30).
	var member := StackMember.new()
	member.id = perception._character.get_instance_id()
	member.terms = {
		"into": into, "join": join, "order_id": "" if join else str(live["id"]),
		"order_hold": true, "order_frame": int(live.get("frame", -1)),
	}
	return into if perception.entry.stack(String(live["opening"]), into).held(member.me()) else ""


## End the live order when it is order `id`, for `why` (`done`, `refused`, `cancelled`): kept as
## ended, so it is no longer the NPC's. One done or refused is the leader's to hear (`take_ended`).
func end(id: Variant, why: String) -> void:
	var held := current()
	if held.is_empty() or str(held.get("id", "")) != str(id):
		return
	var ended := held.duplicate()
	ended["ended"] = why
	perception._memory.remember(&"order", ended, 0.0, "live")
	if why != "cancelled":
		_ended_order = { "id": held["id"], "why": why }


## The order that ended done or refused since the last call (`{ id, why }`), or {}: the controller
## radios it (LD7).
func take_ended() -> Dictionary:
	var out := _ended_order
	_ended_order = {}
	return out


## An ambush ends on first contact (`docs/leadership.md` LD15, D18): a hostile in sight, wherever it
## stands, or shots at the NPC (`under_fire`: hit, or a round landing by it). The order is then done
## and the NPC fights on its own. Footsteps heard and callouts are no contact.
func end_ambush_on_contact() -> void:
	var held := current()
	if String(held.get("kind", "")) != "ambush":
		return
	if (perception.under_fire()
			or perception.sight.visible_now.keys().any(func(id):
				return perception.contacts.hostility.is_hostile(id, perception._memory))):
		end(held["id"], "done")
