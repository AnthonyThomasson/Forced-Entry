extends RefCounted
## Shared helpers for the coordinated-squad tests (not a test itself):
## `const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")`. A watch of the team: one
## record (`new_watch`) filled every physics frame (`tick`, or `watch` for a whole run), its reads
## (`asked`, `gaps`, `took`, `acts_of`, `went_through`) and `percentile`, the statistic the band
## checks take over `gaps`; and `off_spot_tick`, a member's clock off its follow spot. The NPC's
## reads and the spec's numbers are `follow_probe.gd`'s, read there.

const Follow := preload("res://tests/_ai/follow_probe.gd")


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
		var room := _room_of(t, c.global_position)
		if room != "":
			if w["room"].has(c) and w["room"][c] != room:
				if not w["moves"].has(c):
					w["moves"][c] = []
				w["moves"][c].append([t.time, w["room"][c], room])
			w["room"][c] = room
		var a := Follow.act(c)
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
	var b := Follow.brain_of(c)
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


## Watch `nodes` (characters) every physics frame for up to `duration` sim s, or until
## `hooks.stop` (called with the record) returns true; `s` is their squad (or null). `hooks.each`,
## when given, is called every frame with the record. Returns the record (`new_watch`).
static func watch(
	t: TestContext,
	nodes: Array,
	s: Node,
	duration: float,
	hooks: Dictionary = {},
) -> Dictionary:
	var stop: Callable = hooks.get("stop", Callable())
	var each: Callable = hooks.get("each", Callable())
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
	var off: bool = (
		spot != Vector2.INF and member.global_position.distance_to(spot) > Follow.OFF_SPOT
	)
	if off:
		if float(clock.get("since", -1.0)) < 0.0:
			clock["since"] = t.time
		clock["longest"] = maxf(float(clock.get("longest", 0.0)), t.time - float(clock["since"]))
	else:
		clock["since"] = -1.0


## The house room `p` is in (its key), "outside" when out of every room, or "" on a sill (between
## the two: a doorway's wall), read off the test world's rooms.
static func _room_of(t: TestContext, p: Vector2) -> String:
	var near := false
	for r in t.rooms:
		var rect: Rect2 = r["rect"]
		if rect.grow(-Follow.IN_ROOM).has_point(p):
			return String(r["key"])
		if rect.grow(Follow.IN_ROOM).has_point(p):
			near = true
	return "" if near else "outside"
