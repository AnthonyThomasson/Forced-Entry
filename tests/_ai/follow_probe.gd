extends RefCounted
## Shared helpers for the coordinated-squad tests (`docs/leadership.md` LD19 to LD28; not a test
## itself): `const Follow := preload("res://tests/_ai/follow_probe.gd")`. A squad is a coordinated
## team: a member with no order follows its leader (AI or human), fights only near it (the leash),
## picks no goal of its own, and goes in by the leader's doorway as one stack (a `stack` order with
## mode `join`).
##
## The squad is built and bound the way Main does it: declared by the test (`s.squads`, read with
## `t.squad`), or for a squad no setup declares, `team_of` (`MatchBuilder.build_squads`), and its
## reads (`leader()`, `follows`, `follow_spot`, `leash`,
## `view()`) are called on it directly (interface 21). The NPCs are read only through their
## controllers' public reads (`current_act()`, `debug_state()`, `debug_entry()`) and the radio. The
## spec's numbers are consts here, so a test checks the spec and not the code.

const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## The follow file (px): the first follower stands this far back along the leader's trail...
const FOLLOW_GAP := 55.0
## ... and each next one this much further.
const FOLLOW_STEP := 45.0
## The ring (px) a still leader's followers stand on, behind its facing, within its sight.
const FOLLOW_RING := 80.0
## How many rings round a still leader hold slots, each `FOLLOW_STEP` further out than the last.
const FOLLOW_RINGS := 3
## How long (s) a leader stands before it counts as still.
const FOLLOW_STILL_TIME := 0.8
## How far (px) a follower's spot moves before it re-aims its walk.
const FOLLOW_RETARGET := 20.0
## How near (px) its spot a follower is at it.
const FOLLOW_ARRIVE := 10.0
## The leash (px) round the leader's live position a follower fights within.
const LEASH := 320.0
## The break (in leashes) past which a fighting follower re-decides.
const LEASH_BREAK := 1.3
## How far (px) past its place in the file (`band_p50`) a follower's median distance to its leader
## may be over a walk: its walking lag behind a spot that moves on ahead of it, measured 5 to 38 px
## at the median (`follow_leader_search`, `follow_defenders`, `follow_human_leader`). A follower a
## whole place behind (`FOLLOW_STEP` more, and its lag) is past it.
const BAND_LAG := 45.0
## The most (px) nine of a follower's distances to its leader in ten may be.
const BAND_P90 := 260.0
## The stack order's mode for a rally: the leader's own stack brings the team in.
const JOIN := "join"
## How far (px) off its follow spot a follower counts as off it (a ring slot's own radius past a
## body length).
const OFF_SPOT := 80.0
## How long (s) off its spot counts as stuck (LD19: no follower more than 8 s off its spot).
const STUCK_S := 8.0
## Half a wall plus a body: a body this far inside a room's rect is in the room, this far outside
## every rect is out of the house. Between the two it keeps the room it had (a doorway's sill).
const IN_ROOM := 22.0
## The leash chase's world (`chase_hall`): an open hall, the leader (a puppet) at `CHASE_LEAD_AT`,
## the invader NPC `m` beside it, the household target in plain sight of both...
const CHASE_HALL := Rect2(0, 0, 1700, 900)
const CHASE_LEAD_AT := Vector2(300, 450)
const CHASE_NPC_AT := Vector2(350, 510)
const CHASE_TARGET_AT := Vector2(620, 450)
## ... and where the target flees to: far past the leash, in plain sight down the hall.
const CHASE_FLEE_TO := Vector2(1600, 450)
## A body's give past the leash (px): the NPC's own radius and a stride.
const CHASE_GIVE := 40.0


# --- The squad ------------------------------------------------------------------------------------


## The most (px) the `i`-th follower's (0 the first) median distance to its leader may be over a
## walk: its place in the file (`FOLLOW_GAP` + `FOLLOW_STEP` x `i`, LD21) and `BAND_LAG`.
static func band_p50(i: int) -> float:
	return FOLLOW_GAP + FOLLOW_STEP * i + BAND_LAG


## The squad over the characters `members` (spawn order), `human` its human leader or null, built
## and bound as Main builds a side's (`Order.squad`, `MatchBuilder.build_squads`); null for no
## members. For a squad no setup declares (a test's own subset of a match's combatants).
static func team_of(t: TestContext, members: Array, human: Node = null) -> Node:
	if members.is_empty():
		return null
	return Order.squad(t, members[0].get("faction"), members, human)


## A name for `n` in a message.
static func name_of(n: Variant) -> String:
	return String(n.name) if n is Node and is_instance_valid(n) else str(n)


# --- The NPC --------------------------------------------------------------------------------------


## The AI controller of character `c` (the child with `debug_state`), or null for a puppet.
static func brain_of(c: Node) -> Node:
	return TestContext.controller_of(c, &"debug_state") if is_instance_valid(c) else null


## Character `c`'s live decision path (`current_act()`), "" for a puppet.
static func act(c: Node) -> String:
	var b := brain_of(c)
	return String(b.current_act()) if b != null else ""


## Whether character `c` is carrying out a FOLLOW leaf (its decision path starts at the root leaf
## `follow`, primitive `follow`).
static func following(c: Node) -> bool:
	var b := brain_of(c)
	if b == null:
		return false
	return act(c).begins_with("follow") or String(b.debug_state().get("primitive", "")) == "follow"


## Where character `c`'s walk is going now (its navigation agent's target, `debug_state()`'s
## `loco.target`), or INF with none.
static func walk_target(c: Node) -> Vector2:
	var b := brain_of(c)
	if b == null:
		return Vector2.INF
	var to = (b.debug_state().get("loco", {}) as Dictionary).get("target", [])
	return Vector2(to[0], to[1]) if to is Array and to.size() == 2 else Vector2.INF


## Character `c`'s running tactical entry (`debug_entry()`), {} when none.
static func entry(c: Node) -> Dictionary:
	var b := brain_of(c)
	return b.debug_entry() if b != null else {}


## The raw `&"order"` events (`{ topic, data, time }`) of kind `kind` (any when ""), oldest first.
static func raw_orders(t: TestContext, kind := "") -> Array:
	return t.events.filter(func(e): return (
		e["topic"] == &"order" and (kind == "" or String(e["data"].get("kind", "")) == kind)
	))


## The raw entry callouts (`{ topic, data, time }`) of step `step` (any when "") from character
## `who`, oldest first.
static func calls_of(t: TestContext, who: Node, step := "") -> Array:
	return t.events.filter(func(e): return (
		e["topic"] == &"callout"
			and e["data"].get("speaker") == who
			and String(e["data"].get("entry_step", "")) != ""
			and (step == "" or String(e["data"].get("entry_step", "")) == step)
	))


## The raw `&"order"` events of kind `stack` and mode `join`, oldest first.
static func raw_joins(t: TestContext) -> Array:
	return raw_orders(t, Order.STACK).filter(
		func(e): return String(e["data"].get("mode", "")) == JOIN,
	)


## The raw entry claims `who` made of its own (no `order_id`: no order behind them), oldest first.
static func own_claims(t: TestContext, who: Node) -> Array:
	return calls_of(t, who, "claim").filter(
		func(e): return str(e["data"].get("order_id", "")) == "",
	)


## The sim time of `who`'s first entry callout of step `step` about `opening`, or INF.
static func first_call(t: TestContext, who: Node, step: String, opening: String) -> float:
	for e: Dictionary in calls_of(t, who, step):
		if String(e["data"].get("opening", "")) == opening:
			return float(e["time"])
	return INF


## The entry callouts `clear` naming `room` as the room cleared (their data).
static func clears(t: TestContext, room: String) -> Array:
	return t.events_of(&"callout", func(d): return (
		String(d.get("entry_step", "")) == "clear" and String(d.get("cleared_room", "")) == room
	))


## The house room `p` is in (its key), "outside" when out of every room, or "" on a sill (between
## the two: a doorway's wall), read off the test world's rooms.
static func room_of(t: TestContext, p: Vector2) -> String:
	var near := false
	for r in t.rooms:
		var rect: Rect2 = r["rect"]
		if rect.grow(-IN_ROOM).has_point(p):
			return String(r["key"])
		if rect.grow(IN_ROOM).has_point(p):
			near = true
	return "" if near else "outside"


# --- Watching the team ----------------------------------------------------------------------------


## A new per-frame record of a team (`tick` fills it): `samples` (`[{ t, pos: { node: Vector2 },
## facing: { node: Vector2 }, leader: Node }]`, one per frame), `moves` (node -> `[[time, from room,
## to room]]`, each change of room, sills skipped), `acts` (node -> `[[time, act]]`, each new act),
## and what `asked` reads: how many questions each NPC put to Von (a decision walk's levels not
## taken without asking).
static func new_watch() -> Dictionary:
	return { "samples": [], "moves": {}, "acts": {}, "room": {}, "asked": {}, "walk": {} }


## Sample `nodes` (characters) into the record `w` now; the squad `s` (or null) names the leader.
static func tick(w: Dictionary, t: TestContext, nodes: Array, s: Node) -> void:
	var sample := {
		"t": t.time,
		"pos": {},
		"facing": {},
		"leader": s.leader() if s != null else null,
	}
	for c in nodes:
		if not is_instance_valid(c):
			continue
		sample["pos"][c] = c.global_position
		sample["facing"][c] = c.get("facing")
		_count(w, c)
		var room := room_of(t, c.global_position)
		if room != "":
			if w["room"].has(c) and w["room"][c] != room:
				if not w["moves"].has(c):
					w["moves"][c] = []
				w["moves"][c].append([t.time, w["room"][c], room])
			w["room"][c] = room
		var a := act(c)
		if not w["acts"].has(c):
			w["acts"][c] = []
		if a != "" and (w["acts"][c].is_empty() or w["acts"][c].back()[1] != a):
			w["acts"][c].append([t.time, a])
	w["samples"].append(sample)


## The questions character `c` has put to Von so far, by the record `w`.
static func asked(w: Dictionary, c: Node) -> int:
	return int(w["asked"].get(c, 0)) + int(w["walk"].get(c, [0, 0])[1])


## Count the questions of `c`'s decision walk under way into `w`: a new walk (its `decisions` count
## moved on) banks the last one's.
static func _count(w: Dictionary, c: Node) -> void:
	var b := brain_of(c)
	if b == null:
		return
	var st: Dictionary = b.debug_state()
	var d := int(st.get("decisions", 0))
	var asks := (st.get("decision", {}).get("levels", []) as Array).filter(
		func(l): return not bool(l.get("auto", false)),
	).size()
	var walk: Array = w["walk"].get(c, [-1, 0])
	if d != int(walk[0]):
		w["asked"][c] = int(w["asked"].get(c, 0)) + int(walk[1])
		walk = [d, asks]
	else:
		walk[1] = maxi(int(walk[1]), asks)
	w["walk"][c] = walk


## Character `c`'s distance to the leader in each sample of `w` from `since` (sim s) on, skipping
## the samples in which `c` itself leads or the leader is gone.
static func gaps(w: Dictionary, c: Node, since := 0.0) -> Array:
	var out: Array = []
	for s: Dictionary in w["samples"]:
		var lead = s["leader"]
		if float(s["t"]) < since or lead == null or lead == c or not s["pos"].has(c):
			continue
		if not s["pos"].has(lead):
			continue
		out.append((s["pos"][c] as Vector2).distance_to(s["pos"][lead]))
	return out


## Whether `c` ever carried out an act starting with `prefix`, by the record `w`.
static func took(w: Dictionary, c: Node, prefix: String) -> bool:
	return (w["acts"].get(c, []) as Array).any(func(p): return String(p[1]).begins_with(prefix))


## The acts of `c` in `w` as a short string, for a message.
static func acts_of(w: Dictionary, c: Node) -> String:
	return str((w["acts"].get(c, []) as Array).map(
		func(p): return "%.1f %s" % [float(p[0]), p[1]],
	))


## Watch `nodes` (characters) every physics frame for up to `duration` sim s, or until `stop`
## (called with the record) returns true; `s` is their squad (or null). `each`, when valid, is
## called every frame with the record. Returns the record (`new_watch`).
static func watch(
	t: TestContext,
	nodes: Array,
	s: Node,
	duration: float,
	stop := Callable(),
	each := Callable(),
) -> Dictionary:
	var w := new_watch()
	var end := t.time + duration
	while t.time < end:
		tick(w, t, nodes, s)
		if each.is_valid():
			each.call(w)
		if stop.is_valid() and stop.call(w):
			break
		await t.frames(1)
	return w


## The `share` (0..1) percentile of `values` (0 for none).
static func percentile(values: Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(sorted.size() * share))])


## Whether `member`'s moves hold the leader's room change `move` (`[time, from, to]`) within
## `before` s before it to `after` s after it: the member went through the same doorway with it.
static func went_through(
	w: Dictionary,
	member: Node,
	move: Array,
	before := 5.0,
	after := 15.0,
) -> bool:
	return (w["moves"].get(member, []) as Array).any(func(m): return (
		m[1] == move[1]
			and m[2] == move[2]
			and float(m[0]) >= float(move[0]) - before
			and float(m[0]) <= float(move[0]) + after
	))


## Clock `member` standing more than `OFF_SPOT` off the follow spot the squad gives it: call once a
## frame; `clock` keeps `{ since, longest }`, `longest` the longest stretch (s) so far.
static func off_spot_tick(t: TestContext, s: Node, member: Node, clock: Dictionary) -> void:
	var spot: Vector2 = s.follow_spot(member)
	var off: bool = spot != Vector2.INF and member.global_position.distance_to(spot) > OFF_SPOT
	if off:
		if float(clock.get("since", -1.0)) < 0.0:
			clock["since"] = t.time
		clock["longest"] = maxf(float(clock.get("longest", 0.0)), t.time - float(clock["since"]))
	else:
		clock["since"] = -1.0


# --- The leash chase ------------------------------------------------------------------------------


## Lay the leash chase's world into `s`: the open hall `CHASE_HALL`, the puppet `me` (the human
## leader, when a squad is bound) at `CHASE_LEAD_AT` aiming at the target, the invader `m` at
## `CHASE_NPC_AT`, and the household puppet `target` at `CHASE_TARGET_AT` facing down the hall to
## `CHASE_FLEE_TO`; nobody is ever killed (`max_health`) and the target never shoots.
static func chase_hall(s: TestSetup) -> void:
	s.arena(CHASE_HALL)
	Stack.human(s, &"me", CHASE_LEAD_AT, { "aim_point": CHASE_TARGET_AT })
	s.actor(&"m", &"invader", CHASE_NPC_AT, { "max_health": 1_000_000.0 })
	s.actor(
		&"target",
		&"puppet",
		CHASE_TARGET_AT,
		{
			"faction": &"household",
			"max_health": 1_000_000.0,
			"aim_point": CHASE_FLEE_TO,
			"facing": Vector2.RIGHT,
		},
	)
