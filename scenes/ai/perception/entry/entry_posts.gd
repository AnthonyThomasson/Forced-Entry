extends RefCounted
## AI PERCEPTION sub-domain — ENTRY GEOMETRY's posts, a part the entry geometry holds as `posts`:
## where a member ordered to defend a room stands (`defend_spot`, `docs/leadership.md` D2) and where
## one ordered to ambush a doorway waits (`ambush_spot`, LD15). Built once by `AgentEntry`, it holds
## nothing of it: the geometry is handed in at the call (`entry`), so no reference cycle forms.
## Where a helper would take more parameters than the style allows, the entry rides in the frame it
## already takes (`f["entry"]`, set by `_ambush_posts`), which dies with the call. The two public
## calls take the member's place in its order as one `Vector2i` (x which post, y of how many).

## The entry geometry this part is one of, handed in at the call (never held: it holds the part).
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
## A defend spot (`defend_spot`, `docs/leadership.md` D2): how far back from its doorway's wall (px)
## it is sought, at best `DEFEND_DEPTH`...
const DEFEND_DEPTHS := [60.0, 90.0, 120.0, 150.0]
const DEFEND_DEPTH := 100.0
## ... and how far along the wall past the doorway's jamb (px), at best `DEFEND_LATERAL`: off the
## doorway's axis, out of its funnel.
const DEFEND_LATERALS := [30.0, 50.0, 75.0, 100.0]
const DEFEND_LATERAL := 50.0
## Inset (px) of a defend spot from the room's walls (a body and half a wall), and the most a snap
## onto the navmesh may move it.
const DEFEND_INSET := 22.0
const DEFEND_SNAP := 10.0
## A spot within a body (px) of a doorway's width and closer than `DEFEND_FUNNEL_DEPTH` (px) to its
## wall stands in its fatal funnel.
const DEFEND_BODY := 14.0
const DEFEND_FUNNEL_DEPTH := 200.0
## Where (px into the room from the doorway's centre) a defender's sight line to its doorway ends.
const DEFEND_DOOR_IN := 8.0
## An ambush post (`ambush_spot`, `docs/leadership.md` LD15): how far back from the doorway's wall
## (px) it is sought, at best `AMBUSH_DEPTH` (the cover depth of a room's holders, E8)...
const AMBUSH_DEPTHS := [40.0, 70.0, 100.0, 130.0, 160.0]
const AMBUSH_DEPTH := 110.0
## ... and how far along the wall past the doorway's jamb (px): well along it, where the wall hides
## the post from a stack outside.
const AMBUSH_LATERALS := [30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 220.0, 260.0]
## Inset (px) of an ambush post from the room's walls.
const AMBUSH_INSET := 22.0
## How far apart (px) two ambushers' posts on one side of the doorway stand (a stack's slot spacing:
## clear of each other's footprint).
const AMBUSH_SPACING := 44.0
## How far (px) round its post an ambusher may stand once there (it stops within a reach of the
## spot, the behaviour's `orders.DEFEND_REACH`, and a little): a post is hidden only when it is
## hidden there too.
const AMBUSH_SLACK := 12.0

## "<opening id>><room key>" -> the ambush post candidates of that doorway, room side
## (`_ambush_posts`).
var cache := {}


## Where member `nth` of `count` (`place`: x which post, y of how many) holds room `room_key` it was
## ordered to defend (`docs/leadership.md` LD8, D2), and what it watches: the members share out the
## room's doorways (sorted by id; member `nth` takes doorway `nth` mod their number, the extras
## doubling up on the other side of it), each standing back in the room off its doorway's axis, out
## of every doorway's fatal funnel, with a sight line to it and, where there is one, low furniture
## between (cover it sees over); a lone member takes the spot from which it sees the most doorways.
## `{ spot, door, door_pos, doors }`: `door` is the id of the doorway it keeps its gun on ("" for a
## lone member of a room with several: it turns among `doors`, the room's doorways), `door_pos` that
## doorway's centre (INF for none). {} for a room it does not know.
func defend_spot(
	entry: AgentEntry,
	room_key: String,
	place: Vector2i,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	var nth := place.x
	var count := place.y
	var rect: Rect2 = entry.views.room_rect(room_key)
	if rect.size == Vector2.ZERO:
		return {}
	var doors := entry.room_doorways(room_key)
	doors.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	if doors.is_empty():
		return {
			"spot": NavBuilder.snap(map, rect.get_center()),
			"door": "",
			"door_pos": Vector2.INF,
			"doors": doors,
		}
	var lone := count <= 1 and doors.size() > 1
	var own: Dictionary = doors[posmod(nth, doors.size())]
	var round_no := int(float(nth) / float(doors.size()))
	var best := {}
	for d in (doors if lone else [own]):
		var at := _defend_best(entry, _defend_frame(rect, d, doors, round_no, lone), map, space)
		if not at.is_empty() and (best.is_empty() or float(at["score"]) < float(best["score"])):
			best = at
	return {
		"spot": NavBuilder.snap(map, rect.get_center()) if best.is_empty() else best["spot"],
		"door": "" if lone else String(own["id"]),
		"door_pos": Vector2.INF if lone else own["pos"],
		"doors": doors,
	}


## The frame a defend spot by doorway `d` of room `rect` (one of the room's `doors`) is sought in
## (`defend_spot`): `{ id, pos, width, into, along, room, doors, wanted, lone }`, `into` the normal
## into the room, `along` its wall's axis, `wanted` the side of the axis member round `round_no`
## takes (the side with more wall first, then they alternate), `lone` a lone member's.
func _defend_frame(
	rect: Rect2,
	d: Dictionary,
	doors: Array,
	round_no: int,
	lone: bool,
) -> Dictionary:
	var pos: Vector2 = d["pos"]
	var into := AgentEntry.normal_into(rect, pos)
	var along := into.orthogonal()
	var first := _first_side(rect, pos, along)
	return {
		"id": d["id"],
		"pos": pos,
		"width": float(d["width"]),
		"into": into,
		"along": along,
		"room": rect,
		"doors": doors,
		"wanted": first if round_no % 2 == 0 else -first,
		"lone": lone,
	}


## The best defend spot in frame `f` (`_defend_frame`): of the candidates `DEFEND_DEPTHS` back and
## `DEFEND_LATERALS` past the jamb either side (`_defend_candidate`), the first with the lowest
## score (`_defend_score`). `{ score, spot }`, or {} when there is none.
func _defend_best(
	entry: AgentEntry,
	f: Dictionary,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	var best := {}
	for at: Array in _offsets(DEFEND_DEPTHS, DEFEND_LATERALS):
		var c := _defend_candidate(entry, f, _offset_point(f, at), map, space)
		if c.is_empty():
			continue
		var score := _defend_score(f, c, at)
		if best.is_empty() or score < float(best["score"]):
			best = { "score": score, "spot": c["spot"] }
	return best


## The rank of defend candidate `c` (`_defend_candidate`) found at offset `at` (`_offsets`) in frame
## `f`, the lower the better: nearest the best depth and lateral, out of every funnel; a lone
## member's seeing the most doorways, any other's seeing its own doorway, on its `wanted` side; then
## low furniture on the line (cover seen over).
func _defend_score(f: Dictionary, c: Dictionary, at: Array) -> float:
	var depth: float = at[0]
	var lateral: float = at[1]
	var score: float = (absf(depth - DEFEND_DEPTH) + absf(lateral - DEFEND_LATERAL)
			+ float(c["funnel"]) * 1000.0)
	if f["lone"]:
		score -= float(c["sees"]) * 2000.0
	else:
		score += ((0.0 if c["sees_door"].has(f["id"]) else 3000.0)
				+ (0.0 if at[2] == f["wanted"] else 400.0))
	score += (0.0
			if c["cover"].has(f["id"]) or (f["lone"] and not c["cover"].is_empty())
			else 300.0)
	return score


## Every offset a spot back from a doorway is sought at: `[depth, lateral, side]` for each of
## `depths`, each of `laterals` past the jamb and each side of the axis (1, then -1), in that order.
func _offsets(depths: Array, laterals: Array) -> Array:
	var out: Array = []
	for depth: float in depths:
		for lateral: float in laterals:
			for s: int in [1, -1]:
				out.append([depth, lateral, s])
	return out


## The point at offset `at` (`_offsets`) in frame `f` (its doorway's `pos`, `width`, the normal
## `into` the room and the wall's axis `along`): `depth` into the room, `lateral` past the jamb on
## side `side`.
func _offset_point(f: Dictionary, at: Array) -> Vector2:
	var pos: Vector2 = f["pos"]
	var into: Vector2 = f["into"]
	var along: Vector2 = f["along"]
	var width: float = f["width"]
	var depth: float = at[0]
	var lateral: float = at[1]
	var s: int = at[2]
	return pos + into * depth + along * s * (width * 0.5 + lateral)


## The side (1 / -1 along `along`) with more of room `rect`'s wall from door `pos`, 1 when even.
func _first_side(rect: Rect2, pos: Vector2, along: Vector2) -> int:
	return (1 if AgentEntry.wall_length(rect, pos, along)
			>= AgentEntry.wall_length(rect, pos, -along) else -1)


## A candidate defend spot near `raw` in frame `f` (`_defend_frame`, `_ambush_posts`: its `room`
## and the room's `doors`) (`defend_spot`): snapped onto the navmesh inside the room
## (dropped when the snap moves it off), with `funnel` (how many of the room's `doors` it stands in
## the fatal funnel of), `sees` / `sees_door` (the doorways it has a sight line to, how many and
## which) and `cover` (the ids of those with low furniture on the line, which it sees over). {} when
## it is no spot.
func _defend_candidate(
	entry: AgentEntry,
	f: Dictionary,
	raw: Vector2,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	var inner := (f["room"] as Rect2).grow(-DEFEND_INSET)
	if not inner.has_point(raw):
		return {}
	var p := NavBuilder.snap(map, raw)
	if p.distance_to(raw) > DEFEND_SNAP or not inner.has_point(p):
		return {}
	var funnel := 0
	var sees: Dictionary = {}
	var cover: Dictionary = {}
	for d in f["doors"]:
		var pos: Vector2 = d["pos"]
		var into := AgentEntry.normal_into(f["room"], pos)
		var off := p - pos
		if (absf(off.dot(into.orthogonal())) < float(d["width"]) * 0.5 + DEFEND_BODY
				and off.dot(into) < DEFEND_FUNNEL_DEPTH):
			funnel += 1
		var aim := pos + into * DEFEND_DOOR_IN
		if entry._sees(space, p, aim):
			sees[d["id"]] = true
			var hit: Dictionary = entry.vision.raycast(space, p, aim, []) if space != null else {}
			if hit.get("collider") is RigidBody2D:
				cover[d["id"]] = true
	return { "spot": p, "funnel": funnel, "sees": sees.size(), "sees_door": sees, "cover": cover }


## Where member `nth` of `count` (`place`: x which post, y of how many) ordered to ambush a doorway
## from the room it leads into waits, `g` being that way in's entry geometry
## (`AgentEntry.geometry(id, room_key, map, space)`) (`docs/leadership.md` LD15, D17): a post in the
## room, off the doorway's axis, back from its wall and inside the room's walls, out of the fatal
## funnel of every doorway of the room, with a sight line to the threshold, and unseen from outside:
## no sight line to it from any slot or pie step of an entry into the room by that doorway. Among
## the hidden posts, one with low furniture on its line to the threshold (cover it sees over) wins,
## then the nearest `AMBUSH_DEPTH` back; with none hidden, the least seen. Hidden means hidden
## wherever within `AMBUSH_SLACK` of the post the ambusher stops. Members alternate sides of the
## axis (member `nth`: the side with more wall first), and two on one side stand `AMBUSH_SPACING`
## apart. `{ spot, door_pos, seen }`: `door_pos` is the doorway's centre, where its gun goes, `seen`
## how many of those slots and pie steps see the post (0: hidden). {} for an empty `g` (a doorway or
## room it does not know), or no post.
func ambush_spot(
	entry: AgentEntry,
	g: Dictionary,
	place: Vector2i,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	var nth := place.x
	var count := place.y
	if g.is_empty():
		return {}
	var posts := _ambush_posts(entry, g, map, space)
	if posts.is_empty():
		return {}
	var first := _first_side(g["room"], g["pos"], g["along"])
	var taken: Array = []
	var pick := {}
	for k in mini(nth, maxi(count - 1, 0)) + 1:
		var wanted := first if k % 2 == 0 else -first
		pick = {}
		for c: Dictionary in posts:
			if taken.any(func(t): return (t as Vector2).distance_to(c["spot"]) < AMBUSH_SPACING):
				continue
			var score := float(c["score"]) + (0.0 if int(c["side"]) == wanted else 50_000.0)
			if pick.is_empty() or score < float(pick["score"]):
				pick = { "score": score, "spot": c["spot"], "seen": c["seen"] }
		if pick.is_empty():
			return {}
		taken.append(pick["spot"])
	return { "spot": pick["spot"], "door_pos": g["pos"], "seen": pick["seen"] }


## The candidate ambush posts of entry geometry `g` (into its room `into`, the side the ambusher
## waits on), kept once worked out on a baked map: `{ spot, side, seen, score }`, `side` the side of
## the axis it lies on, `seen` how many slots and pie steps see it, `score` the post's rank before
## the side is weighed (the lower the better: hidden first, out of every funnel, cover on its line,
## then nearest `AMBUSH_DEPTH`).
func _ambush_posts(
	entry: AgentEntry,
	g: Dictionary,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Array:
	var room_key := String(g["into"])
	var key := "%s>%s" % [g["id"], room_key]
	if cache.has(key):
		return cache[key]
	var f := {
		"id": g["id"],
		"pos": g["pos"],
		"width": float(g["width"]),
		"into": -(g["out"] as Vector2),
		"along": g["along"],
		"room": g["room"],
		"doors": entry.room_doorways(room_key),
		"entry": entry,
	}
	var observers := _observers_of(g)
	var out: Array = []
	for at: Array in _offsets(AMBUSH_DEPTHS, AMBUSH_LATERALS):
		var post := _ambush_post(f, at, observers, map, space)
		if not post.is_empty():
			out.append(post)
	if NavBuilder.ready(map):
		cache[key] = out  # Only keep what was snapped onto a baked map.
	return out


## The ambush post at offset `at` (`_offsets`) in frame `f` (`_ambush_posts`: the doorway, its room
## and the room's doorways, and the entry geometry it is one of, `entry`), seen from
## `observers` (`_observers_of`): `{ spot, side, seen, score }`,
## or {} when it is no post (outside the room's inset, no spot there, no sight line to the doorway,
## or on its axis).
func _ambush_post(
	f: Dictionary,
	at: Array,
	observers: Array,
	map: RID,
	space: PhysicsDirectSpaceState2D,
) -> Dictionary:
	var entry: AgentEntry = f["entry"]
	var rect: Rect2 = f["room"]
	var raw := _offset_point(f, at)
	if not rect.grow(-AMBUSH_INSET).has_point(raw):
		return {}
	var c := _defend_candidate(entry, f, raw, map, space)
	if c.is_empty() or not c["sees_door"].has(f["id"]):
		return {}
	var p: Vector2 = c["spot"]
	if absf((p - (f["pos"] as Vector2)).dot(f["along"])) < float(f["width"]) * 0.5 + DEFEND_BODY:
		return {}  # On the axis.
	var seen := _seen_by(entry, space, observers, p)
	var score := (float(seen) * 1000.0 + float(c["funnel"]) * 500.0
			+ (0.0 if c["cover"].has(f["id"]) else 300.0) + absf(float(at[0]) - AMBUSH_DEPTH))
	return { "spot": p, "side": at[2], "seen": seen, "score": score }


## Who could see an ambush post of entry geometry `g` from outside: its `lookouts`, then each side's
## slots and pie steps (side 1 first).
func _observers_of(g: Dictionary) -> Array:
	var observers: Array = (g["lookouts"] as Array).duplicate()
	for side in [1, -1]:
		observers.append_array(g["slots"][side])
		observers.append_array(g["pie"][side])
	return observers


## How many of `observers` see post `p` (`_sees_from`); for a post none sees, the most that see any
## of the 8 points `AMBUSH_SLACK` round it.
func _seen_by(
	entry: AgentEntry,
	space: PhysicsDirectSpaceState2D,
	observers: Array,
	p: Vector2,
) -> int:
	var seen := observers.filter(func(o): return _sees_from(entry, space, o, p)).size()
	if seen == 0:
		for k in 8:
			var q := p + Vector2.from_angle(TAU * k / 8.0) * AMBUSH_SLACK
			seen = maxi(
				seen,
				observers.filter(func(o): return _sees_from(entry, space, o, q)).size(),
			)
	return seen


## Whether someone standing at `from` sees `to` (over low cover; walls and tall furniture block it),
## at any distance and whichever way it faces: what a stack outside could see of a post once it
## looks.
func _sees_from(
	entry: AgentEntry,
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	to: Vector2,
) -> bool:
	return space == null or entry.vision.sight_hit(space, from, to, []).is_empty()
