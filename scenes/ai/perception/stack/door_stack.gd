extends RefCounted
## AI PERCEPTION sub-domain — STACK · a doorway's stack as the radio describes it
## (`docs/tactical-entry.md` E2, E6, E16 to E22; `docs/leadership.md` LD13, LD18): built from the
## doorway's `geometry` (agent_entry.gd `geometry`) and the claims heard on it (`team`,
## claim_ledger.gd `claims`, `StackClaim.decode`'s fields), it settles every slot rule the same way
## for whoever asks: an NPC's entry, its snapshot, the human's `PlayerStack` and the side's `Squad`.
##
## A member asking about itself passes `me`, its own claim as it stands (it never hears its own on
## the radio): `{ id, slot, side, want, frame, pos, move_up, stuns, frags, order_id, order_bang,
## order_mode, order_hold, order_go, order_side, into, step }`, each optional (`id` and `slot` its
## instance id and slot, 0 while it is claiming; `want` the side it asks for; `frame` / `pos` the
## frame its slot was claimed on and where it stood then, E2; `move_up` the slot it moved up from;
## `into` the room it goes into).
## The human is a member like any other (E16): no AI moves up into its slot, it never moves up
## itself and it never throws the stack's grenade. The layout statics (`stack_slots`, `side_for`,
## `stack_point`, `place`, `crossing_order`, `stack_side`, `holds_slot`, `is_tail`, `free_slot`) are
## the one place a slot becomes a point. Read-only: it never changes the claims it was built from.

const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
## How far (px) out in front of the door a slot stands when the doorway has no file to lay it in.
const NO_FILE_OUT := 28.0

## The doorway's geometry ({} when only the claims are asked about).
var geometry := {}
## The claims on the doorway, lowest slot first (shared with the ledger: never changed here).
var team: Array = []


func _init(g := {}, claims: Array = []) -> void:
	geometry = g
	team = claims


## The slot member `me` holds (`me.slot`, 0: it is claiming now), or the first one free for it,
## among the claims (`free_slot`): same-frame claims settle by distance with `me.frame` and
## `me.pos`, a move-up holds against a plain claim, and its holder takes the slot it freed (E2).
func slot_for(me: Dictionary) -> int:
	var mine := {}
	if me.has("frame"):
		mine = {
			"frame": int(me["frame"]), "pos": me.get("pos", Vector2.ZERO), "g": geometry,
			"side": int(me.get("side", 0)), "move_up": int(me.get("move_up", 0)),
		}
	return free_slot(team, int(me.get("id", 0)), int(me.get("slot", 0)), mine)


## Where member `me` (its `slot`, the side it asks for `want`) stands among the claims (E19 to E22):
## `{ slot, side, place, point }`, its side the one `side_for` gives that slot (`want` while its
## wall has room, E21), its place in that side's file and its point (`Vector2.INF` for a slot a
## dead end does not hold). A claim still on the slot a member moved up into counts at the slot that
## member freed (E2, the move-up rewrite), whoever asks.
func settle(me: Dictionary) -> Dictionary:
	var n := int(me.get("slot", 0))
	var claims := _moved_up(me)
	var on := side_for(geometry, claims, n, int(me.get("want", me.get("side", 0))))
	var members: Array = claims + [{ "id": int(me.get("id", 0)), "slot": n, "side": on }]
	return {
		"slot": n,
		"side": on,
		"place": place(members, on, n),
		"point": stack_point(geometry, members, n, on),
	}


## Where every member stands in its slot (`{ id, slot, side, point, me? }`, `me` marked): the
## claims, with the move-up rewrite, and `me`'s own, each laid among them all as `settle` lays it.
func points(me: Dictionary) -> Array:
	var members: Array = _moved_up(me) + [_member(me).merged({ "me": true }, true)]
	return members.map(
		func(m): return m.merged({
			"point": stack_point(geometry, members, int(m["slot"]), int(m["side"])),
		}, true)
	)


## The stack as the markers draw it: `[{ n, point, holder, held, there, mine, side, row }]` for
## slot 1 up to the last taken (`me`'s among them when given), each where its holder stands it (its
## holder's side; a free one on `me`'s `want`, else the team's side), a slot a dead end does not
## hold left out; `holder` the instance id holding it (0: none), `there` its holder standing in it
## (`StackClaim.IN_SLOT`), `mine` `me`'s or else the human's, `side` the side its point lies on and
## `row` its file (1 against the wall, 2 a step out). The points are `settle`'s.
func layout(me := {}) -> Array:
	var members := _moved_up(me)
	if not me.is_empty():
		members = members + [_member(me).merged({ "me": true }, true)]
	var holder := {}
	var top := 0
	for m in members:
		top = maxi(top, int(m["slot"]))
		if not holder.has(int(m["slot"])) or m.get("me", false):
			holder[int(m["slot"])] = m
	var lead := int(me.get("want", 0))
	if lead == 0:
		lead = stack_side(geometry, members, geometry["pos"])
	var out: Array = []
	for n in range(1, top + 1):
		var m: Dictionary = holder.get(n, {})
		var on := (int(m["side"])
				if not m.is_empty() and int(m["side"]) != 0
				else side_for(geometry, members, n, lead))
		var at := _laid(geometry, members, n, on)
		if at["point"] == Vector2.INF:
			continue  # A slot the doorway does not hold (a dead end's).
		out.append({
			"n": n, "point": at["point"], "holder": int(m.get("id", 0)), "held": not m.is_empty(),
			"there": not m.is_empty() and StackClaim.in_slot(str(m.get("step", ""))),
			"mine": not m.is_empty() and (bool(m.get("me", false)) or bool(m.get("human", false))),
			"side": on if _on_wall(geometry, n) else AgentEntry.side_of(geometry, at["point"]),
			"row": int(at["row"]),
		})
	return out


## The members in the order they cross (E6, E19: `crossing_order`), `me` among them when given
## (marked `me`).
func crossing(me := {}) -> Array:
	var members := team
	if not me.is_empty():
		members = members + [_member(me).merged({ "me": true }, true)]
	return crossing_order(members)


## The claims that cross before member `me` (the first to cross first).
func ahead(me: Dictionary) -> Array:
	var out: Array = []
	for m in crossing(me):
		if m.get("me", false):
			break
		out.append(m)
	return out


## The claims that cross after member `me`.
func behind(me: Dictionary) -> Array:
	var out: Array = []
	var past := false
	for m in crossing(me):
		if m.get("me", false):
			past = true
		elif past:
			out.append(m)
	return out


## Whether any ally claims the doorway at all (at any live step).
func claimed() -> bool:
	return not team.is_empty()


## Whether anyone holds a place in the stack (a claim at a `StackClaim.STACKING` step).
func stacking() -> bool:
	return team.any(func(m): return StackClaim.stacking(m["step"]))


## Whether a member is crossing (`going_in`) or through the doorway.
func going_in() -> bool:
	return team.any(func(m): return m["step"] == "going_in" or StackClaim.through(m["step"]))


## The instance id of the member who throws the stack's grenade of kind `kind` (`&"frag"` or a
## stun) (E17, LD14), or -1 when nobody can: slot 2 if its holder carries one, else the lowest slot
## that does; `me` (its `stuns` / `frags`) among them. Never the human, which throws nothing for the
## stack.
func thrower(kind: StringName, me := {}) -> int:
	var key := "frags" if kind == &"frag" else "stuns"
	var carriers: Array = team.filter(
		func(m): return int(m[key]) > 0 and not bool(m["human"]),
	).map(func(m): return { "id": m["id"], "slot": m["slot"] })
	if int(me.get(key, 0)) > 0:
		carriers.append({ "id": int(me.get("id", 0)), "slot": int(me.get("slot", 0)) })
	if carriers.is_empty():
		return -1
	carriers.sort_custom(StackClaim.by_slot)
	for c: Dictionary in carriers:
		if c["slot"] == 2:
			return c["id"]
	return carriers[0]["id"]


## The order the stack goes in under (LD9): `me`'s own (its `order_id`, the order's fields and the
## room it goes into, `into`), else the lowest slot's of the claims that carry one (an unordered
## member that joins an ordered stack follows it, D10). {} for a stack nobody was ordered to.
func order_claim(me := {}) -> Dictionary:
	if str(me.get("order_id", "")) != "":
		return {
			"order_id": str(me["order_id"]), "order_bang": bool(me.get("order_bang", false)),
			"order_mode": str(me.get("order_mode", "")),
			"order_hold": bool(me.get("order_hold", false)),
			"order_go": bool(me.get("order_go", false)), "order_side": int(me.get("order_side", 0)),
			"into": str(me.get("into", "")),
		}
	for m in team:
		if m["order_id"] != "":
			return m
	return {}


## Whether the held stack under order `order_id`, going into room `into`, has had its go off the
## radio (LD13): a claim under that order says the go came (`order_go`), or a member of that stack
## is crossing or through the doorway into `into`, one under the order or the human (D14: the human
## leader in the stack stepping in is its go). A claim left from an earlier entry through the
## doorway (under no order or another, or into the other room) releases nothing.
func released(order_id: String, into: String) -> bool:
	return team.any(
		func(m):
			if m["order_id"] != order_id and not m["human"]:
				return false
			if m["order_id"] == order_id and m["order_go"]:
				return true
			return m["into"] == into and (m["step"] == "going_in" or StackClaim.through(m["step"]))
	)


## The chain every member claims and keeps its slot by, an NPC's entry and the human's
## `PlayerStack` alike (E2, E19 to E22): the slot `slot_for` gives member `me`, whether the doorway
## has it (`held`, `has_slot`: a dead end holds only so many, E20), the side it asks for in it
## (`want`, its own weighing, called with that slot) and where it then stands (`settle`):
## `{ slot, held, side, place, point }`. A member whose slot changes is no longer moving up (E2), so
## its `move_up` is dropped for the settling.
func claim(me: Dictionary, want: Callable) -> Dictionary:
	var n := slot_for(me)
	var asked := me.merged({ "slot": n, "want": int(want.call(n)) }, true)
	if n != int(me.get("slot", 0)):
		asked["move_up"] = 0
	var at := settle(asked)
	at["held"] = has_slot(n)
	return at


## A split stack's side for member `me` (its `id` and `slot`; D6, E19): `own`, the side it stands on
## (it reaches it without crossing the doorway's view), but when that side holds two more of the
## stack than the other with `me` there, the other side for the last of that side to have claimed
## (the highest slot, then the highest instance id), so the sides differ by one at most. Every
## member weighs it the same way off the radio; it moves the one member, and once the sides are even
## nobody moves again.
func split_side(me: Dictionary, own: int) -> int:
	var n := int(me.get("slot", 0))
	var id := int(me.get("id", 0))
	var mine := 1 + team.filter(func(m): return int(m["side"]) == own).size()
	var other := team.filter(func(m): return int(m["side"]) == -own).size()
	if mine - other < 2:
		return own
	for m in team:
		if (int(m["side"]) == own
				and (int(m["slot"]) > n or (int(m["slot"]) == n and int(m["id"]) > id))):
			return own  # A later claimer on this side moves instead.
	return -own


## The back of the stack for a member holding `slot` (E2: the slots go by arrival): the slot behind
## the last one claimed, when it is not already the last and the doorway has a slot there (E20); 0
## when there is none to take.
func back_slot(slot: int) -> int:
	var last := 0
	for m in team:
		last = maxi(last, int(m["slot"]))
	if last < slot or not has_slot(last + 1):
		return 0
	return last + 1


## The slot an ordered member (instance id `self_id`) would take in its stack (1 = the point), its
## order's living recipients' ids `to_ids` in the order the order names them: after those named
## before it, and after every claim on the doorway from anyone else, so a dead end's extras are
## known before anyone claims (E20, LD9).
func order_place(to_ids: Array, self_id: int) -> int:
	var before := maxi(to_ids.find(self_id), 0)
	for m in team:
		if not to_ids.has(m["id"]) and m["id"] != self_id:
			before += 1
	return before + 1


## Whether the doorway has a slot `slot` at all (E20: a dead end holds only so many).
func has_slot(slot: int) -> bool:
	return holds_slot(geometry, slot)


## Whether slot `slot` is one of the stack's tail (E20's fallback).
func tail(slot: int) -> bool:
	return is_tail(geometry, slot)


## The side the team stacks on, seen from `from` (`stack_side`).
func team_side(from: Vector2) -> int:
	return stack_side(geometry, team, from)


## Where slot 1 stands on side `side` with nobody yet claiming (`Vector2.INF`: no slot there).
func first_point(side: int) -> Vector2:
	return stack_point(geometry, [], 1, side_for(geometry, [], 1, side))


## The lower slots member `me` (standing in its slot `slot` on side `side`, asking for `want`) may
## move up into (E2, the rule part; the walk and whether the latecomer would meet it are the
## entry's): `[{ holder, slot, point, stack }]`, each a claim still at `claim` holding a lower slot
## on `me`'s side alone, none of them the human's (no AI moves up into its slot) nor one moving up
## itself, whose slot stays on `me`'s side with the two swapped (`stack` the stack so, `point` where
## `me` would stand). None once a member has begun the pie, the bang or the crossing: the order of
## the stack stands.
func move_up_vacancies(me: Dictionary) -> Array:
	var begun := func(m):
		return m["pie"] or m["step"] in ["bang", "going_in"] or StackClaim.through(m["step"])
	if team.any(begun):
		return []
	var n := int(me.get("slot", 0))
	var on := int(me.get("side", 0))
	var id := int(me.get("id", 0))
	var out: Array = []
	for h in team:
		var vacancy := int(h["slot"])
		var taken := func(m): return int(m["slot"]) == vacancy and m["id"] != h["id"]
		if (vacancy >= n or int(h["side"]) != on or h["step"] != "claim" or h["human"]
				or int(h["move_up"]) > 0 or team.any(taken)):
			continue
		var swapped: Array = team.map(
			func(m): return m.merged({ "slot": n }, true) if m["id"] == h["id"] else m,
		)
		if side_for(geometry, swapped, vacancy, int(me.get("want", on))) != on:
			continue
		var point := stack_point(
			geometry, swapped + [{ "id": id, "slot": vacancy, "side": on }], vacancy, on,
		)
		if point != Vector2.INF:
			out.append({
				"holder": h, "slot": vacancy, "point": point,
				"stack": (get_script() as GDScript).new(geometry, swapped),
			})
	return out


## The claims with the move-up rewrite (E2): the claim still on the slot a member moved up into
## (its `move_up`, `me`'s too) counts at the slot that member freed, until it claims that one.
func _moved_up(me: Dictionary) -> Array:
	var freed := {}  # slot moved up into -> the slot freed.
	for m in team:
		if int(m["move_up"]) > 0:
			freed[int(m["slot"])] = int(m["move_up"])
	if int(me.get("move_up", 0)) > 0:
		freed[int(me.get("slot", 0))] = int(me["move_up"])
	if freed.is_empty():
		return team
	return team.map(
		func(m):
			if freed.has(int(m["slot"])) and int(m["move_up"]) == 0:
				return m.merged({ "slot": freed[int(m["slot"])] }, true)
			return m
	)


## `me` as a member of the layout: `{ id, slot, side, step }`.
func _member(me: Dictionary) -> Dictionary:
	return {
		"id": int(me.get("id", 0)), "slot": int(me.get("slot", 0)),
		"side": int(me.get("side", 0)), "step": str(me.get("step", "")),
	}


# --- The layout and claim rules (statics) --------------------------------------------------------


## Where a stack of `count` going in by geometry `g` stands, its point on side `side` (1 / -1 along
## the wall) where that side has room: `[{ n, point, side, row }]`, slot 1 (the point) first. The
## one rule every stack is laid out by (E20 to E22, `_lay_slots`): one slot per member, but on a
## dead end only as many as its room holds.
static func stack_slots(g: Dictionary, count: int, side: int) -> Array:
	var members: Array = []
	var out: Array = []
	for n in range(1, count + 1):
		if not holds_slot(g, n):
			break
		var on := side_for(g, members, n, side)
		members.append({ "id": n, "slot": n, "side": on })
	for m: Dictionary in members:
		var n := int(m["slot"])
		var at := _laid(g, members, n, int(m["side"]))
		out.append({
			"n": m["slot"],
			"point": at["point"],
			"side": m["side"] if _on_wall(g, n) else AgentEntry.side_of(g, at["point"]),
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
		var at := _laid(g, claims, slot, pref)
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
static func stack_point(g: Dictionary, members: Array, slot: int, side: int) -> Vector2:
	return _laid(g, members, slot, side)["point"]


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
static func _on_wall(g: Dictionary, slot: int) -> bool:
	return g.get("kind", "wall") == "wall" and slot <= int(g.get("wall_n", AgentEntry.MAX_SLOTS))


## `{ point, row }` of slot `slot` on side `side` among `members` (see `stack_point`).
static func _laid(g: Dictionary, members: Array, slot: int, side: int) -> Dictionary:
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
		return _wins(claims, current, int(mine.get("side", 0)), other, self_id, mine)
	if current > 0 and (not taken.has(current) or taken[current].all(holds)):
		return current
	for other in taken.get(current, []):
		var freed := int(other.get("move_up", 0))
		if freed > 0 and not taken.has(freed) and int(mine.get("move_up", 0)) == 0:
			return freed  # An ally moved up into this slot (E2): this NPC takes the one it freed.
	var slot := 1
	while taken.has(slot):
		var gives_way := func(other):
			return (int(other["claim_frame"]) == int(mine.get("frame", -2))
					and _wins(claims, slot, int(other["side"]), other, self_id, mine))
		if taken[slot].all(gives_way):
			# Claimed on the frame this NPC claimed on, by someone farther from it: this NPC takes
			# it, and the other gives it up.
			return slot
		slot += 1
	return slot


## Whether this NPC (`self_id`, `mine`: see `free_slot`) holds slot `slot` on side `side` against
## ally `other`'s claim on it: the one that moved up into it, of a move-up and a claim that is not
## one (E2); else by distance to the slot's point (laid among the claims but these two) when both
## claimed it on the same frame on the same side, else (and at an even distance) by instance id.
static func _wins(
	claims: Array,
	slot: int,
	side: int,
	other: Dictionary,
	self_id: int,
	mine: Dictionary,
) -> bool:
	if (int(other.get("move_up", 0)) > 0) != (int(mine.get("move_up", 0)) > 0):
		# A move-up (E2) holds the slot it stepped into against the claim it moved up past.
		return int(mine.get("move_up", 0)) > 0
	if (not mine.is_empty()
			and int(other["claim_frame"]) >= 0
			and int(other["claim_frame"]) == int(mine["frame"])
			and (side == 0 or side == int(other["side"]))):
		var rest: Array = claims.filter(func(m): return m["id"] != other["id"])
		var at := stack_point(mine["g"], rest, slot, int(other["side"]))
		if at != Vector2.INF:
			var own: float = (mine["pos"] as Vector2).distance_to(at)
			var theirs: float = (other["claim_pos"] as Vector2).distance_to(at)
			if absf(own - theirs) > 0.5:
				return own < theirs
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
