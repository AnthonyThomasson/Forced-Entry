extends RefCounted
## AI PERCEPTION sub-domain — STACK · a doorway's stack as the radio describes it
## (`docs/tactical-entry.md` E2, E6, E16 to E22; `docs/leadership.md` LD13, LD18): built from the
## doorway's `geometry` (agent_entry.gd `geometry`) and the claims heard on it (`team`,
## claim_ledger.gd `claims`, `StackClaim.decode`'s fields), it settles every slot rule the same way
## for whoever asks: an NPC's entry, its snapshot, the human's `PlayerStack` and the side's `Squad`.
##
## A member asking about itself passes `me`, its own claim as it stands (it never hears its own on
## the radio), in the radio's field names (`StackMember.me`, stack_member.gd, builds it): `{ id,
## slot, side, want, claim_frame, claim_pos, move_up, step, crossed_frame, stuns, frags, into,
## order_id, order_bang, order_mode, order_hold, order_go, order_side, order_frame, join, human,
## leader, own }`, each optional (`id` and `slot` its instance id and slot, 0 while it is claiming;
## `want` the side it asks for; `claim_frame` / `claim_pos` the frame its slot was claimed on and
## where it stood then, E2; `move_up` the slot it moved up from; `into` the room it goes into).
## The human is a member like any other (E16): no AI moves up into its slot, it never moves up
## itself and it never throws the stack's grenade. The layout and claim rules it settles them by
## are stack_layout.gd's statics (`StackLayout`), the one place a slot becomes a point. Read-only:
## it never changes the claims it was built from.

const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const StackLayout := preload("res://scenes/ai/perception/stack/stack_layout.gd")

## The doorway's geometry ({} when only the claims are asked about).
var geometry := {}
## The claims on the doorway, lowest slot first (shared with the ledger: never changed here).
var team: Array = []


func _init(g := {}, claims: Array = []) -> void:
	geometry = g
	team = claims


## The slot member `me` holds (`me.slot`, 0: it is claiming now), or the first one free for it,
## among the claims (`StackLayout.free_slot`): same-frame claims settle by distance with
## `me.claim_frame` and `me.claim_pos`, a move-up holds against a plain claim, and its holder takes
## the slot it freed (E2).
func slot_for(me: Dictionary) -> int:
	var mine := {}
	if me.has("claim_frame"):
		mine = {
			"frame": int(me["claim_frame"]), "pos": me.get("claim_pos", Vector2.ZERO),
			"g": geometry,
			"side": int(me.get("side", 0)), "move_up": int(me.get("move_up", 0)),
		}
	return StackLayout.free_slot(team, int(me.get("id", 0)), int(me.get("slot", 0)), mine)


## Where member `me` (its `slot`, the side it asks for `want`) stands among the claims (E19 to E22):
## `{ slot, side, place, point }`, its side the one `StackLayout.side_for` gives that slot (`want`
## while its wall has room, E21), its place in that side's file and its point (`Vector2.INF` for a
## slot a dead end does not hold). A claim still on the slot a member moved up into counts at the
## slot that member freed (E2, the move-up rewrite), whoever asks.
func settle(me: Dictionary) -> Dictionary:
	var n := int(me.get("slot", 0))
	var claims := _moved_up(me)
	var on := StackLayout.side_for(geometry, claims, n, int(me.get("want", me.get("side", 0))))
	var members: Array = claims + [{ "id": int(me.get("id", 0)), "slot": n, "side": on }]
	return {
		"slot": n,
		"side": on,
		"place": StackLayout.place(members, on, n),
		"point": StackLayout.point(geometry, members, n, on),
	}


## Where every member stands in its slot (`{ id, slot, side, point, me? }`, `me` marked): the
## claims, with the move-up rewrite, and `me`'s own, each laid among them all as `settle` lays it.
func points(me: Dictionary) -> Array:
	var members: Array = _moved_up(me) + [_member(me).merged({ "me": true }, true)]
	return members.map(
		func(m): return m.merged({
			"point": StackLayout.point(geometry, members, int(m["slot"]), int(m["side"])),
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
		lead = StackLayout.stack_side(geometry, members, geometry["pos"])
	var out: Array = []
	for n in range(1, top + 1):
		var m: Dictionary = holder.get(n, {})
		var on := (int(m["side"])
				if not m.is_empty() and int(m["side"]) != 0
				else StackLayout.side_for(geometry, members, n, lead))
		var at := StackLayout.laid(geometry, members, n, on)
		if at["point"] == Vector2.INF:
			continue  # A slot the doorway does not hold (a dead end's).
		out.append({
			"n": n, "point": at["point"], "holder": int(m.get("id", 0)), "held": not m.is_empty(),
			"there": not m.is_empty() and StackClaim.in_slot(str(m.get("step", ""))),
			"mine": not m.is_empty() and (bool(m.get("me", false)) or bool(m.get("human", false))),
			"side": on if StackLayout.on_wall(
				geometry,
				n,
			) else AgentEntry.side_of(geometry, at["point"]),
			"row": int(at["row"]),
		})
	return out


## The members in the order they cross (E6, E19: `StackLayout.crossing_order`), `me` among them when
## given (marked `me`).
func crossing(me := {}) -> Array:
	var members := team
	if not me.is_empty():
		members = members + [_member(me).merged({ "me": true }, true)]
	return StackLayout.crossing_order(members)


## The claims that cross before member `me` (the first to cross first).
func ahead(me: Dictionary) -> Array:
	var out: Array = []
	for m in crossing(me):
		if m.get("me", false):
			break
		out.append(m)
	return out


## Whether anyone holds a place in the stack (a claim at a `StackClaim.STACKING` step).
func stacking() -> bool:
	return team.any(func(m): return StackClaim.stacking(m["step"]))


## Whether a member is crossing (`going_in`) or through the doorway.
func going_in() -> bool:
	return team.any(func(m): return StackClaim.crossing(m["step"]))


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
			"order_frame": int(me.get("order_frame", -1)), "into": str(me.get("into", "")),
		}
	for m in team:
		if m["order_id"] != "":
			return m
	return {}


## Whether the held stack under order `order_id`, issued on frame `since`, going into room `into`,
## has had its go off the radio (LD13): any claim heard says so (`_releases`). `order_id` "" is the
## human leader's rally whose joins were posted on frame `since` (LD24, D38).
func released(order_id: String, into: String, since: int) -> bool:
	return team.any(func(m): return _releases(m, order_id, into, since))


## The go member `me`'s stack holds for (LD13, D38): `{ order_id, into, since }`, the order
## `order_claim` says it goes in under when that order holds for its leader's go (`order_id` its
## id, `since` its frame), else the human leader's rally it joined (`me`'s own join waiting for the
## go, `order_hold`, else the lowest slot's such join among the claims: an unordered member that
## joins it follows it, as D10): `order_id` "", `since` the frame its joins were posted on. {} for a
## stack that holds for nobody: no hold, an AI leader's rally, an independent stack.
func hold(me: Dictionary) -> Dictionary:
	var ordered := order_claim(me)
	if not ordered.is_empty():
		if not bool(ordered.get("order_hold", false)):
			return {}
		return {
			"order_id": str(ordered["order_id"]), "into": str(ordered.get("into", "")),
			"since": int(ordered.get("order_frame", -1)),
		}
	var rally := _rally(me)
	if rally.is_empty():
		return {}
	return { "order_id": "", "into": str(rally["into"]), "since": int(rally["order_frame"]) }


## Whether member `me`'s stack is held for its leader's go (LD13, D38): it holds for one (`hold`),
## `me` has not latched it (`order_go`) and no claim says it came (`released`). Nobody in a held
## stack slices the pie, listens, calls a bang or crosses.
func held(me: Dictionary) -> bool:
	if bool(me.get("order_go", false)):
		return false
	var go := hold(me)
	return not go.is_empty() and not released(go["order_id"], go["into"], go["since"])


## The mode member `me`'s stack goes in (LD9, LD14, D1, D38, E17): `quiet`, `stun` or `frag`. An
## ordered stack's is its order's (`order_claim`), quiet once a member under that order gave its
## grenade up (`bang_off`, D1 / D15); a human leader's rally's is the mode its go named (`me`'s own
## latched go, else a joiner of that rally saying its go came), quiet before it and on a go no menu
## named (the leader stepping in), or once a member of the rally gave its grenade up; any other
## stack's is its first claimer's (E17): `stun` while every claim says bang and none gave it up,
## else `quiet`. "" with nobody claiming and no order nor rally: the member goes its own way.
func mode(me: Dictionary) -> String:
	var ordered := order_claim(me)
	if not ordered.is_empty():
		var id := str(ordered["order_id"])
		if team.any(func(m): return m["bang_off"] and m["order_id"] == id):
			return "quiet"
		return str(ordered["order_mode"])
	var rally := _rally(me)
	if not rally.is_empty():
		return _rally_mode(me, rally)
	if team.is_empty():
		return ""
	return "stun" if team.all(func(m): return m["bang"] and not m["bang_off"]) else "quiet"


## The chain every member claims and keeps its slot by (`StackMember.claim`: an NPC's entry, the
## slot its snapshot offers it, and the human's `PlayerStack` alike; E2, E19 to E22): the slot
## `slot_for` gives member `me`, whether the doorway has it (`held`, `StackLayout.holds_slot`: a
## dead end holds only so many, E20), and where it then stands (`settle`) on the side it asks for
## (`me.want`, weighed by the member for that slot and handed in as a value): `{ slot, held, side,
## place, point }`. A member whose slot changes is no longer moving up (E2), so its `move_up` is
## dropped for the settling.
func claim(me: Dictionary) -> Dictionary:
	var n := slot_for(me)
	var asked := me.merged({ "slot": n }, true)
	if n != int(me.get("slot", 0)):
		asked["move_up"] = 0
	var at := settle(asked)
	at["held"] = StackLayout.holds_slot(geometry, n)
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
	if last < slot or not StackLayout.holds_slot(geometry, last + 1):
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


## The side the team stacks on, seen from `from` (`stack_side`).
func team_side(from: Vector2) -> int:
	return StackLayout.stack_side(geometry, team, from)


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
		if StackLayout.side_for(geometry, swapped, vacancy, int(me.get("want", on))) != on:
			continue
		var point := StackLayout.point(
			geometry, swapped + [{ "id": id, "slot": vacancy, "side": on }], vacancy, on,
		)
		if point != Vector2.INF:
			out.append({
				"holder": h, "slot": vacancy, "point": point,
				"stack": (get_script() as GDScript).new(geometry, swapped),
			})
	return out


## Whether claim `m` is the go of the held stack under order `order_id`, issued on frame `since`,
## into room `into` (D14): under that order, it says the go came (`order_go`) or it is crossing or
## through into `into`; the human's (its claim carries no order to scope it by), it is crossing or
## through into `into` on a crossing begun on or after `since` (`crossed_frame`), the human leader
## in the stack stepping in. A crossing whose frame or order's frame is unknown (-1) cannot be told
## from one left on the radio from an earlier entry, so it releases nothing, nor does a claim under
## no order or another but the human's, or one into the other room.
func _releases(m: Dictionary, order_id: String, into: String, since: int) -> bool:
	var crosses: bool = m["into"] == into and StackClaim.crossing(m["step"])
	if order_id == "":
		return _releases_rally(m, crosses, since)
	if m["order_id"] == order_id:
		return m["order_go"] or crosses
	if not m["human"]:
		return false
	return crosses and since >= 0 and int(m["crossed_frame"]) >= since


## Whether claim `m` is the go of the human leader's rally whose joins were posted on frame `since`
## (D38; `crosses`: `m` is crossing or through into the rally's room): a joiner of that rally (its
## `order_frame` the same) saying its go came or crossing, or the human crossing on a crossing begun
## on or after `since` (the leader stepping in). A join or crossing left on the radio from an
## earlier rally, or of unknown frame, releases nothing.
func _releases_rally(m: Dictionary, crosses: bool, since: int) -> bool:
	if since < 0:
		return false
	if m["join"]:
		return int(m["order_frame"]) == since and (m["order_go"] or crosses)
	return m["human"] and crosses and int(m["crossed_frame"]) >= since


## The human leader's rally member `me` holds for (D38): `me` itself when it is a join waiting for
## its leader's go (`join`, `order_hold`), else the lowest slot's claim that is and is still at a
## stacking step (`StackClaim.stacking`): a joiner of an earlier rally at the doorway, gone through
## into the room it cleared, is left from that entry and forms no rally now. `{ into,
## order_frame }`, {} when it joined none.
func _rally(me: Dictionary) -> Dictionary:
	if bool(me.get("join", false)) and bool(me.get("order_hold", false)):
		return { "into": str(me.get("into", "")), "order_frame": int(me.get("order_frame", -1)) }
	for m in team:
		if m["join"] and m["order_hold"] and StackClaim.stacking(m["step"]):
			return m
	return {}


## The mode of the rally `rally` (`_rally`) member `me` holds for (D38): the mode its go named (a
## stun or a frag, `me`'s latched one, else a joiner's of that rally whose go came), unless a member
## of the rally gave its grenade up; else quiet.
func _rally_mode(me: Dictionary, rally: Dictionary) -> String:
	var since := int(rally["order_frame"])
	var of_rally := func(m): return m["join"] and int(m["order_frame"]) == since
	if team.any(func(m): return of_rally.call(m) and m["bang_off"]):
		return "quiet"
	if bool(me.get("order_go", false)) and StackClaim.throws_first(str(me.get("order_mode", ""))):
		return str(me["order_mode"])
	for m in team:
		if of_rally.call(m) and m["order_go"] and StackClaim.throws_first(m["order_mode"]):
			return m["order_mode"]
	return "quiet"


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
