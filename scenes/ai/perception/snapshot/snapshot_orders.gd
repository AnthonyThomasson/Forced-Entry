extends RefCounted
## AI PERCEPTION sub-domain — SNAPSHOT ORDERS. Writes the ORDER option group Von is offered
## (`docs/leadership.md` LD5, LD6): the one option the order this NPC's leader gave it makes, a
## defend, an entry, a join, a hold or an ambush, with the primitive it runs and its params. A pure
## read of the doorway geometry, the entry claims heard and the shared vocabulary.
## `agent_snapshot.gd` holds it (`_orders`) beside the other option groups (`snapshot_options.gd`)
## and calls it from `build()`.

const SnapshotVocab = preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const StackClaim = preload("res://scenes/ai/perception/stack/stack_claim.gd")
const StackLayout := preload("res://scenes/ai/perception/stack/stack_layout.gd")

## The shared vocabulary and tuning; see snapshot_vocab.gd.
var _v: SnapshotVocab
## The NPC's body, handed in once by `bind`.
var _character: Node
## The doorway geometry; see agent_entry.gd.
var _entry: RefCounted
## The allies' entry claims heard on the radio; see stack/claim_ledger.gd.
var _ledger: RefCounted


## Capture the shared vocabulary and the collaborators the group reads (`sources`). Called once by
## `AgentSnapshot.setup()`.
func setup(vocab: SnapshotVocab, sources: SnapshotSources) -> void:
	_v = vocab
	_entry = sources.entry
	_ledger = sources.ledger


## Hand in the NPC's body. Called once by `AgentSnapshot.bind()`.
func bind(character: Node) -> void:
	_character = character


## The order this NPC's leader gave it (`docs/leadership.md` LD5, LD6), as the one option of the
## ORDER node, carrying the primitive it runs and that primitive's params: `defend_room` is a
## `defend` of the room at this member's defend spot with its gun on its doorway (D2,
## `EntryPosts.defend_spot`: the members of the order share the room's doorways out in the order
## `to` names them); `stack` is an `entry` through the ordered doorway into the ordered room
## (`opening`, `into`, `bang`, `mode` (LD14), `wait_go` and `go` (LD13), and the side: `stack_at` or
## `split`), a join (the leader's own stack, LD24, `StackClaim.is_join`) the member's own entry
## joining it (`opening`, `into`, `join`, `bang` false: no side or mode of the order's), none at a
## dead end with no slot for it; `ambush` (LD15) is an `ambush` of the doorway from the ordered room
## at this member's post with its gun on the threshold (`EntryPosts.ambush_spot`: `opening`, `room`,
## `spot`, `door_pos`). Each carries the order's `order_id`. A stack at a dead end that holds no
## slot for this member (its place, `DoorStack.order_place`, past what the room holds, E20:
## `_has_place`) is a `hold` where it stands instead, the order kept and refused (`refused` in its
## params: the behaviour radios it). Empty with no order, or one this NPC cannot carry out (a room
## or doorway it does not know): refused, and dropped.
func group(ctx: Dictionary, order: Dictionary, rooms: Array) -> Dictionary:
	if order.is_empty():
		return { "summary": "", "options": [] }
	var option := {}
	match String(order.get("kind", "")):
		"defend_room":
			option = _defend_order_option(ctx, order, rooms)
		"stack":
			option = _stack_order_option(ctx, order, rooms)
		"ambush":
			option = _ambush_order_option(ctx, order, rooms)
	if option.is_empty():
		return { "summary": "", "options": [] }
	return { "summary": option["label"], "options": [option] }


## The ORDER option of a `defend_room` order: a `defend` of the room at this member's defend spot
## (`EntryPosts.defend_spot`), its gun on its doorway; {} for a room it does not know or no spot.
func _defend_order_option(ctx: Dictionary, order: Dictionary, rooms: Array) -> Dictionary:
	var room := HouseRooms.by_key(rooms, String(order.get("room", "")))
	if room.is_empty():
		return {}
	var to: Array = (order.get("to", []) as Array).filter(
		func(m): return is_instance_valid(m),
	)
	var nth := maxi(to.find(_character), 0)
	var at: Dictionary = _entry.posts.defend_spot(
		_entry,
		String(room["key"]),
		Vector2i(nth, to.size()),
		ctx["map"],
		ctx["space"],
	)
	if at.is_empty():
		return {}
	var params := {
		"room": String(room["key"]),
		"spot": at["spot"],
		"door": at["door"],
		"order_id": order["id"],
	}
	if at["door_pos"] != Vector2.INF:
		params["door_pos"] = at["door_pos"]
	var label := "defend the %s" % _v.room_name(room["type"])
	return {
		"id": "defend_%s" % room["key"], "label": label, "desc": label,
		"primitive": &"defend", "params": params, "tags": { "inside": true },
	}


## The ORDER option of a `stack` order: a join (`_join_order_option`), an ordered entry
## (`_entry_order_option`), or a hold where it stands at a dead end with no slot for it
## (`_hold_order_option`); {} for a room or doorway it does not know, or a join with no slot.
func _stack_order_option(ctx: Dictionary, order: Dictionary, rooms: Array) -> Dictionary:
	var into := HouseRooms.by_key(rooms, String(order.get("into", "")))
	if into.is_empty():
		return {}
	var g: Dictionary = _entry.geometry(
		String(order.get("opening", "")),
		String(into["key"]),
		ctx["map"],
		ctx["space"],
	)
	if g.is_empty():
		return {}
	if StackClaim.is_join(order):
		# The leader's own stack (LD24, D10): the member's own entry, joining it (no side, no mode
		# of the order's). A dead end with no slot for it is no join: refused, it follows again
		# (LD25).
		return _join_order_option(ctx, order, into) if _has_place(order, g, ctx) else {}
	if not _has_place(order, g, ctx):
		# Past what a dead end holds (E20, rule 6): no slot for it. The order stands, refused: it
		# holds where it is.
		return _hold_order_option(ctx, order, into)
	return _entry_order_option(ctx, order, into)


## The ORDER option of a join into room `into`: the member's own `entry`, joining the leader's
## stack (`join`, `bang` false, the order's id).
func _join_order_option(ctx: Dictionary, order: Dictionary, into: Dictionary) -> Dictionary:
	var joined := "the doorway into the %s" % _v.room_name(into["type"])
	return {
		"id": "stack_%s" % order["opening"], "label": joined, "desc": joined,
		"primitive": &"entry",
		"params": {
			"opening": String(order["opening"]), "into": String(into["key"]),
			"bang": false, "join": true, "order_id": order["id"],
		},
		"tags": { "inside": _v.is_inside(ctx["self_pos"]) },
	}


## The ORDER option of a stack order into room `into` with no slot for this member: a `hold` where
## it stands, the order kept and refused (`refused` in its params).
func _hold_order_option(ctx: Dictionary, order: Dictionary, into: Dictionary) -> Dictionary:
	var hold := ("hold where you are: no room at the doorway into the %s"
			% _v.room_name(into["type"]))
	return {
		"id": "hold_%s" % order["opening"], "label": hold, "desc": hold,
		"primitive": &"hold", "params": { "order_id": order["id"], "refused": true },
		"tags": { "inside": _v.is_inside(ctx["self_pos"]) },
	}


## The ORDER option of a stack order into room `into`: an `entry` the order's way (`bang`, `mode`,
## `wait_go`, `go`, the side: `split` or `stack_at`).
func _entry_order_option(ctx: Dictionary, order: Dictionary, into: Dictionary) -> Dictionary:
	var bang := bool(order.get("bang", false))
	var params := {
		"opening": String(order["opening"]), "into": String(into["key"]), "bang": bang,
		"mode": String(order["mode"]), "wait_go": bool(order.get("wait_go", false)),
		"go": bool(order.get("go", false)), "split": bool(order.get("split", false)),
		"order_id": order["id"],
	}
	if order.get("stack_at") is Vector2:
		params["stack_at"] = order["stack_at"]
	var label := ("the doorway into the %s%s"
			% [_v.room_name(into["type"]), " with a %s" % params["mode"] if bang else ""])
	return {
		"id": "stack_%s" % order["opening"], "label": label, "desc": label,
		"primitive": &"entry", "params": params,
		"tags": { "inside": _v.is_inside(ctx["self_pos"]) },
	}


## The ORDER option of an `ambush` order: an `ambush` of the doorway from the ordered room at this
## member's post (`EntryPosts.ambush_spot`), its gun on the threshold; {} for a room it does not
## know or no post.
func _ambush_order_option(ctx: Dictionary, order: Dictionary, rooms: Array) -> Dictionary:
	var room := HouseRooms.by_key(rooms, String(order.get("room", "")))
	if room.is_empty():
		return {}
	var to: Array = (order.get("to", []) as Array).filter(
		func(m): return is_instance_valid(m),
	)
	var at: Dictionary = _entry.posts.ambush_spot(
		_entry,
		_entry.geometry(
			String(order.get("opening", "")), String(room["key"]), ctx["map"], ctx["space"],
		),
		Vector2i(maxi(to.find(_character), 0), to.size()), ctx["map"], ctx["space"],
	)
	if at.is_empty():
		return {}
	var params := {
		"opening": String(order["opening"]), "room": String(room["key"]),
		"spot": at["spot"], "door_pos": at["door_pos"], "order_id": order["id"],
	}
	var label := "ambush the doorway from the %s" % _v.room_name(room["type"])
	return {
		"id": "ambush_%s" % order["opening"], "label": label, "desc": label,
		"primitive": &"ambush", "params": params, "tags": { "inside": true },
	}


## Whether the doorway of stack order `order` (geometry `g`) has a slot for this NPC: the one it
## would take (`DoorStack.order_place`), after the living recipients of the order named before it in
## `to` and after every claim on the doorway from anyone else (the radio), so a dead end's extras
## are known before anyone claims (E20).
func _has_place(order: Dictionary, g: Dictionary, ctx: Dictionary) -> bool:
	var to: Array = (order.get("to", []) as Array).filter(
		func(m): return is_instance_valid(m) and m.get("is_dead") != true,
	)
	var stack: RefCounted = _ledger.stack(String(order.get("opening", "")), g)
	return StackLayout.holds_slot(
		stack.geometry,
		stack.order_place(to.map(func(m): return m.get_instance_id()), ctx["self_id"]),
	)
