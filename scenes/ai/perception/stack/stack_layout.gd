extends RefCounted
## AI PERCEPTION sub-domain — STACK · the layout and claim rules of a doorway's stack
## (`docs/tactical-entry.md` E2, E6, E19 to E22): where a stack's slots stand (`slots`, `point`,
## `side_for`, `place`), whether a doorway has a slot (`holds_slot`, `is_tail`), the free slot a
## claim takes (`free_slot`), the side a stack forms on (`stack_side`) and the order it crosses in
## (`crossing_order`), and the slot's point and file (`laid`, `on_wall`). The one place a slot
## becomes a point: `DoorStack` reads it for its own doorway, and the entry, the snapshot and the
## human's `PlayerStack` read it beside it. Static, preloaded (no `class_name`).

const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
## How far (px) out in front of the door a slot stands when the doorway has no file to lay it in.
const NO_FILE_OUT := 28.0


## Where a stack of `count` going in by geometry `g` stands, its point on side `side` (1 / -1 along
## the wall) where that side has room: `[{ n, point, side, row }]`, slot 1 (the point) first. The
## one rule every stack is laid out by (E20 to E22, `_lay_slots`): one slot per member, but on a
## dead end only as many as its room holds.
static func slots(g: Dictionary, count: int, side: int) -> Array:
	var members: Array = []
	var out: Array = []
	for n in range(1, count + 1):
		if not holds_slot(g, n):
			break
		var on := side_for(g, members, n, side)
		members.append({ "id": n, "slot": n, "side": on })
	for m: Dictionary in members:
		var n := int(m["slot"])
		var at := laid(g, members, n, int(m["side"]))
		out.append({
			"n": m["slot"],
			"point": at["point"],
			"side": m["side"] if on_wall(g, n) else AgentEntry.side_of(g, at["point"]),
			"row": at["row"],
		})
	return out


## The side of the door the member holding slot `slot` stacks on, wanting side `preferred` (the
## team's, its own on a split stack, the order's), among the claims `claims` (E21): its side while
## that side's wall has room for it, else the other side's while it has, else a second file on its
## side, then on the other. Past what the wall holds (`seq`), and on a layout with no files
## (`views`, `open_floor`, `dead_end`), the side its slot lies on.
static func side_for(g: Dictionary, claims: Array, slot: int, preferred: int) -> int:
	var pref := preferred if preferred != 0 else 1
	if g.get("kind", "wall") != "wall" or slot > int(g.get("wall_n", AgentEntry.MAX_SLOTS)):
		var at := laid(g, claims, slot, pref)
		return AgentEntry.side_of(g, at["point"]) if at["point"] != Vector2.INF else pref
	var files: Dictionary = g["files"]
	var row1: Dictionary = g["row1"]
	var here := place(claims, pref, slot)
	var there := place(claims, -pref, slot)
	if here <= int(row1[pref]):
		return pref
	if there <= int(row1[-pref]):
		return -pref
	if here <= (files[pref] as Array).size():
		return pref
	if there <= (files[-pref] as Array).size():
		return -pref
	return pref


## Where the member holding slot `slot` on side `side` stands, among the stack's `members` (the
## claims, its own among them or not); INF for a slot a dead end does not hold.
static func point(g: Dictionary, members: Array, slot: int, side: int) -> Vector2:
	return laid(g, members, slot, side)["point"]


## Whether a stack going in by `g` has a slot `slot` at all: a dead end holds only as many as its
## wall and open floor do (E20); any slot elsewhere.
static func holds_slot(g: Dictionary, slot: int) -> bool:
	return (not g.get("capped", false)
			or slot <= int(g.get("wall_n", 0)) + (g.get("seq", []) as Array).size())


## Whether slot `slot` of a stack going in by `g` is one of its tail (E20's fallback: the members a
## small room cannot hold, who hold in the room they came by as rear security and never cross).
static func is_tail(g: Dictionary, slot: int) -> bool:
	return not g.get("capped", false) and g.has("seq") and slot >= int(g.get("tail_from", 999))


## Whether slot `slot` of a stack going in by `g` stands in a file against the wall (`wall`, within
## `wall_n`): its side is the one it was laid on; past it, the side its point lies on.
static func on_wall(g: Dictionary, slot: int) -> bool:
	return g.get("kind", "wall") == "wall" and slot <= int(g.get("wall_n", AgentEntry.MAX_SLOTS))


## `{ point, row }` of slot `slot` on side `side` among `members` (see `point`).
static func laid(g: Dictionary, members: Array, slot: int, side: int) -> Dictionary:
	var wall_n := int(g.get("wall_n", AgentEntry.MAX_SLOTS))
	if slot > wall_n and g.has("seq"):
		var seq: Array = g["seq"]
		var i := slot - wall_n - 1
		if seq.is_empty() or (g.get("capped", false) and i >= seq.size()):
			return { "point": Vector2.INF, "row": 1 }
		return seq[mini(i, seq.size() - 1)]
	if g.get("kind", "wall") == "views":
		var before := func(m): return int(m["slot"]) != slot and int(m["slot"]) <= wall_n
		var count := mini(maxi(members.filter(before).size() + 1, slot), wall_n)
		var lead := side
		for m in members:
			if int(m["slot"]) == 1 and int(m["side"]) != 0:
				lead = int(m["side"])
		var lay := AgentEntry.views_layout(g, count, lead if lead != 0 else 1)
		if lay.is_empty():
			return { "point": g["pos"] + (g["out"] as Vector2) * NO_FILE_OUT, "row": 1 }
		return lay[clampi(slot - 1, 0, lay.size() - 1)]
	var file: Array = g["files"][side if side != 0 else 1]
	if file.is_empty():
		file = g["files"][-side if side != 0 else -1]
	if file.is_empty():
		return { "point": g["pos"] + (g["out"] as Vector2) * NO_FILE_OUT, "row": 1 }
	return file[clampi(place(members, side, slot) - 1, 0, file.size() - 1)]


## The lowest stack slot (1 = the point) not claimed by an ally in `claims` (claim_ledger.gd
## `claims`), for the NPC with instance id `self_id` that holds `current` (0: it is claiming now).
## Claims made on the same physics frame settle by distance (E2), so their walks do not cross: with
## `mine` (`{ frame, pos, g, side }`: the frame this NPC claims or claimed on, where it stood then,
## the doorway's geometry and, for `current`, its side), a slot claimed on that same frame by an
## ally farther from the slot's point than this NPC is taken from it, and of two such claims on one
## slot the nearer keeps it (each reads the other's `claim_frame` and `claim_pos` off the radio, so
## both settle the same way; a slot given up for another keeps the claim's frame and spot, so the
## settling goes on down the stack). Otherwise, or at an even distance, the lower instance id keeps
## a slot two claim. A claim that moved up into a slot (E2: its `move_up`, the slot it came from,
## which `mine` carries for this NPC's own) holds it against one that did not, and the NPC that held
## it takes the freed one.
static func free_slot(claims: Array, self_id: int, current := 0, mine := {}) -> int:
	var taken := {}
	for m in claims:
		taken[m["slot"]] = taken.get(m["slot"], []) + [m]
	var holds := func(other):
		var verdict := _verdict(claims, current, int(mine.get("side", 0)), other, mine)
		return _settles(verdict, self_id, other)
	if current > 0 and (not taken.has(current) or taken[current].all(holds)):
		return current
	for other in taken.get(current, []):
		var freed := int(other.get("move_up", 0))
		if freed > 0 and not taken.has(freed) and int(mine.get("move_up", 0)) == 0:
			return freed  # An ally moved up into this slot (E2): this NPC takes the one it freed.
	var slot := 1
	while taken.has(slot):
		var gives_way := func(other): return _gives_way(claims, slot, other, self_id, mine)
		if taken[slot].all(gives_way):
			# Claimed on the frame this NPC claimed on, by someone farther from it: this NPC takes
			# it, and the other gives it up.
			return slot
		slot += 1
	return slot


## Whether ally `other` gives slot `slot` up to this NPC (`self_id`, `mine`: see `free_slot`): it
## claimed it on the frame this NPC claims on, and this NPC holds it against it.
static func _gives_way(
	claims: Array,
	slot: int,
	other: Dictionary,
	self_id: int,
	mine: Dictionary,
) -> bool:
	if int(other["claim_frame"]) != int(mine.get("frame", -2)):
		return false
	var verdict := _verdict(claims, slot, int(other["side"]), other, mine)
	return _settles(verdict, self_id, other)


## Who holds slot `slot` on side `side`, this NPC (`mine`: see `free_slot`) or ally `other` by its
## claim on it: 1 this NPC, -1 the ally, 0 when neither settles it. The one that moved up into it
## holds it, of a move-up and a claim that is not one (E2); else the nearer to the slot's point
## (laid among the claims but these two) when both claimed it on the same frame on the same side.
static func _verdict(
	claims: Array,
	slot: int,
	side: int,
	other: Dictionary,
	mine: Dictionary,
) -> int:
	if (int(other.get("move_up", 0)) > 0) != (int(mine.get("move_up", 0)) > 0):
		# A move-up (E2) holds the slot it stepped into against the claim it moved up past.
		return 1 if int(mine.get("move_up", 0)) > 0 else -1
	if (not mine.is_empty()
			and int(other["claim_frame"]) >= 0
			and int(other["claim_frame"]) == int(mine["frame"])
			and (side == 0 or side == int(other["side"]))):
		var rest: Array = claims.filter(func(m): return m["id"] != other["id"])
		var at := point(mine["g"], rest, slot, int(other["side"]))
		if at != Vector2.INF:
			var own: float = (mine["pos"] as Vector2).distance_to(at)
			var theirs: float = (other["claim_pos"] as Vector2).distance_to(at)
			if absf(own - theirs) > 0.5:
				return 1 if own < theirs else -1
	return 0


## Whether this NPC (instance id `self_id`) holds a slot against ally `other` on `_verdict`'s
## `verdict`: as it settles, else (and at an even distance) by the lower instance id.
static func _settles(verdict: int, self_id: int, other: Dictionary) -> bool:
	if verdict != 0:
		return verdict > 0
	return self_id < int(other["id"])


## The side of the door (1 / -1 along its wall, see `geometry`) the stack in `claims` stacks on: the
## side the point (the slot 1 claim in `claims`) stacks on; with no point yet, the side with more
## wall to stack against; when both have the same, the side `self_pos` is on. Every member works it
## out the same way, so the stack forms on one side unless a member cannot get there
## (`stack_side_from`, E19).
static func stack_side(g: Dictionary, claims: Array, self_pos: Vector2) -> int:
	for m in claims:
		if m["slot"] == 1 and m["side"] != 0:
			return m["side"]
	if int(g["side"]) != 0:
		return int(g["side"])
	return AgentEntry.side_of(g, self_pos)


## The members of a stack (`members`: claims with `id`, `slot` and `side`, this member's own among
## them) in the order they cross (E6, E19): by slot on a one-sided stack; on a split one the point
## (the lowest slot), then the front man of the other side, then the sides take turns, each side's
## file in slot order (one that runs out leaves the rest to the other).
static func crossing_order(members: Array) -> Array:
	var sorted := members.duplicate()
	sorted.sort_custom(StackClaim.by_slot)
	if sorted.is_empty():
		return sorted
	var lead_side := int(sorted[0]["side"])
	var lead: Array = sorted.filter(
		func(m): return int(m["side"]) == lead_side or int(m["side"]) == 0,
	)
	var other: Array = sorted.filter(
		func(m): return int(m["side"]) != lead_side and int(m["side"]) != 0,
	)
	if other.is_empty():
		return sorted
	var out: Array = []
	for i in maxi(lead.size(), other.size()):
		if i < lead.size():
			out.append(lead[i])
		if i < other.size():
			out.append(other[i])
	return out


## The place (1 = nearest the door) in its side's file of the member holding stack slot `slot` on
## side `side`: the slots are numbered across both sides in the order they were claimed, so a split
## stack (E19) leaves out the claims on the other side ahead of it (`claims`, this
## member's own left out or not). On a one-sided stack the place is the slot.
static func place(claims: Array, side: int, slot: int) -> int:
	var across := 0
	for m in claims:
		if int(m["side"]) != side and int(m["side"]) != 0 and int(m["slot"]) < slot:
			across += 1
	return maxi(slot - across, 1)
