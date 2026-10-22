extends RefCounted
## The match-assembly module's helper (`MatchBuilder.populate`): where and how a match's NPCs are
## placed. Defenders go to a clear spot in a random room, the invader team in one group outside the
## house, out of sight of its exterior doorways (`spawn_invader_team`); each NPC is handed the house
## through
## `MatchBuilder.bind_npc`, added under the match's `World` node and recorded in `combatants` (the
## spectator camera, the match HUD and the overlays observe that list). Like `main.gd` it knows the
## NPC scenes and the Navigation domain's `furniture_holes`; the placement rules live here so the
## root only wires domains.

## The house defender, dropped into one of the generated rooms.
const DEFENDER_SCENE := preload("res://scenes/ai/npc_defender.tscn")
## The house invader, dropped just outside the house. Same AI, different data.
const INVADER_SCENE := preload("res://scenes/ai/npc_invader.tscn")
## A doorway's view (its `wedge`, `docs/tactical-entry.md` E18), which the invader team starts out
## of.
const AgentDoorViews := preload("res://scenes/ai/perception/agent_door_views.gd")
## Random points tried in a room, after its centre, before `clear_spot` gives up.
const SPAWN_TRIES := 32
## Rings round a group's point (`spawn_invader_team`) tried for a member before it gives up: six
## hold 130 spots.
const GROUP_RINGS := 6
## How deep (px) an exterior doorway's view reaches out of it, as the NPCs' own (the controller's
## `door_view_depth`, `docs/tactical-entry.md` E18): an invader team starts out of the wedge of
## every front and exit doorway (`AgentDoorViews.wedge`), so a defender inside does not see it
## through the doorway as the match starts.
const DOOR_VIEW_DEPTH := 450.0
## How close (px) to an exterior doorway's centre no invader of the team starts: out of its wedge
## yet beside it, the team would be heard and met at the door.
const DOOR_CLEAR := 200.0
## The share of the perimeter the team's point moves on by, clockwise, while it is in an exterior
## doorway's view (`DOOR_VIEW_DEPTH`, `DOOR_CLEAR`): a hundredth, so the whole ring is tried in a
## hundred steps.
const PERIMETER_STEP := 0.01

## The match's `World` node the NPCs are added under.
var world: Node2D = null
## Minimum clearance (px) from solid furniture a character is dropped with (twice that from another
## combatant).
var spawn_clearance: float = 20.0
## How far outside the house's bounding box (px) invaders are dropped.
var invader_margin: float = 80.0
## Every NPC placed so far, in spawn order.
var combatants: Array = []
## The house's doorways (`WorldGen.get_openings`), handed to every NPC it places alongside the
## rooms.
var openings: Array = []


## Drop defender number `index` at a clear spot (`clear_spot`) in a random room. `rng` is seeded
## from `house_seed` so a pinned layout also pins the NPCs. Added after the house, so it draws above
## it. `rooms` is WorldGen.get_rooms(house), already fetched by the caller.
func spawn_defender(rooms: Array, rng: RandomNumberGenerator, index: int) -> void:
	if rooms.is_empty():
		return
	var room: Dictionary = rooms[rng.randi() % rooms.size()]
	add_npc(DEFENDER_SCENE, npc_name("Defender", index), clear_spot(room["rect"], rng), rooms)


## Where a character can be dropped in room `rect`: its centre when clear, else the first clear
## point of SPAWN_TRIES drawn from `rng` (inset from the walls). Clear = at least `spawn_clearance`
## from every solid furniture footprint (Navigation's `furniture_holes`, read off the shapes, so it
## is right on the frame the house is built) and twice that from every combatant already placed. The
## centre when nothing is clear.
func clear_spot(rect: Rect2, rng: RandomNumberGenerator) -> Vector2:
	var holes := NavBuilder.furniture_holes(world)
	var taken: Array = []
	for c in combatants:
		if is_instance_valid(c):
			taken.append((c as Node2D).global_position)
	var centre := rect.get_center()
	if is_clear(centre, holes, taken):
		return centre
	var inner := rect.grow(-spawn_clearance * 2.0)
	if inner.size.x > 0.0 and inner.size.y > 0.0:
		for i in SPAWN_TRIES:
			var p := inner.position + Vector2(rng.randf(), rng.randf()) * inner.size
			if is_clear(p, holes, taken):
				return p
	GameLog.say("No clear spawn spot in the room at %s; using its centre" % centre)
	return centre


## Whether `p` keeps `spawn_clearance` from every footprint in `holes` and twice that from every
## point in `taken`.
func is_clear(p: Vector2, holes: Array, taken: Array) -> bool:
	for q in taken:
		if p.distance_to(q) < spawn_clearance * 2.0:
			return false
	for poly: PackedVector2Array in holes:
		if Geometry2D.is_point_in_polygon(p, poly):
			return false
		for i in poly.size():
			var edge_end: Vector2 = poly[(i + 1) % poly.size()]
			var closest := Geometry2D.get_closest_point_to_segment(p, poly[i], edge_end)
			if closest.distance_to(p) < spawn_clearance:
				return false
	return true


## Drop an invader team of `count` in one group outside the house, so the squad starts together:
## packed round one point of the perimeter `invader_margin` px out of the rooms' bounding box, drawn
## from `rng` (so a pinned house seed pins it), or round `around` when given (the human invader's
## spot, which a member then keeps clear of as of any combatant). The drawn point, and every member
## round it, keeps out of the views of the house's exterior doorways (`_door_views`, `_unseen`):
## while the drawn point is in one, the point walks on round the perimeter by `PERIMETER_STEP` to
## the first that is not, and when none is, the drawn point is used and logged. Round the human no
## such rule holds: the team packs round wherever the human stands. Each member takes the spot
## `_group_spot` gives it, nearest the point first. `front_entranceworld` is injected so each heads
## straight for the entrance rather than circling.
func spawn_invader_team(
	rooms: Array,
	rng: RandomNumberGenerator,
	count: int,
	front_entranceworld: Vector2,
	around := Vector2.INF,
) -> void:
	if rooms.is_empty():
		return
	var bounds: Rect2 = rooms[0]["rect"]
	for room in rooms:
		bounds = bounds.merge(room["rect"])
	var centre := around
	var views: Array = []
	if centre == Vector2.INF:
		views = _door_views(rooms)
		centre = _unseen_point(bounds.grow(invader_margin), rng.randf(), views)
	var holes := NavBuilder.furniture_holes(world)
	for i in count:
		var taken: Array = []
		for c in combatants:
			if is_instance_valid(c):
				taken.append((c as Node2D).global_position)
		if around != Vector2.INF:
			taken.append(around)
		add_npc(
			INVADER_SCENE,
			npc_name("Invader", i),
			_group_spot(centre, rooms, bounds, holes, taken, views),
			rooms,
			front_entranceworld,
		)


## The spot nearest `centre` for one more member of a group: `centre` itself, then the points of
## rings twice `spawn_clearance` apart round it (about one per twice `spawn_clearance` along each
## ring), the first that is clear of `holes` and `taken` (`is_clear`), `_outdoors` and out of
## `views` (`_unseen`). `centre` when none is.
func _group_spot(
	centre: Vector2,
	rooms: Array,
	bounds: Rect2,
	holes: Array,
	taken: Array,
	views: Array,
) -> Vector2:
	var step := spawn_clearance * 2.0
	for ring in GROUP_RINGS + 1:
		var slots := maxi(1, floori(TAU * ring))
		for k in slots:
			var p := centre + Vector2.from_angle(TAU * k / slots) * step * ring
			if _outdoors(p, rooms, bounds) and _unseen(p, views) and is_clear(p, holes, taken):
				return p
	GameLog.say("No clear spawn spot round %s; using it" % centre)
	return centre


## Whether `p` stands out of every room by `spawn_clearance` and within twice `invader_margin` of
## `bounds` (the rooms' bounding box), on the walkable ring round the house.
func _outdoors(p: Vector2, rooms: Array, bounds: Rect2) -> bool:
	for room in rooms:
		if (room["rect"] as Rect2).grow(spawn_clearance).has_point(p):
			return false
	return p.distance_to(p.clamp(bounds.position, bounds.end)) <= invader_margin * 2.0


## The views of the house's exterior doorways (the front entrance and the exits among `openings`),
## each `{ pos, wedge }`: the doorway's centre and its `AgentDoorViews.wedge` from the room behind
## it, `DOOR_VIEW_DEPTH` px deep.
func _door_views(rooms: Array) -> Array:
	var out: Array = []
	for o: Dictionary in openings:
		if not (o.get("front", false) or o.get("exit", false)):
			continue
		for room: Dictionary in rooms:
			if (o.get("rooms", []) as Array).has(room["key"]):
				out.append({
					"pos": o["pos"],
					"wedge": AgentDoorViews.wedge(o, room["rect"], DOOR_VIEW_DEPTH),
				})
	return out


## Whether `p` is out of every one of `views` (`_door_views`): out of its wedge and `DOOR_CLEAR` px
## or more from its doorway.
func _unseen(p: Vector2, views: Array) -> bool:
	for v: Dictionary in views:
		if p.distance_to(v["pos"]) < DOOR_CLEAR:
			return false
		if Geometry2D.is_point_in_polygon(p, v["wedge"]):
			return false
	return true


## The point at fraction `frac` round the perimeter of `rect` when it is out of `views` (`_unseen`),
## else the first that is, walking on clockwise by `PERIMETER_STEP`; the point at `frac`, logged,
## when none is.
func _unseen_point(rect: Rect2, frac: float, views: Array) -> Vector2:
	for i in roundi(1.0 / PERIMETER_STEP):
		var p := perimeter_point(rect, fposmod(frac + i * PERIMETER_STEP, 1.0))
		if _unseen(p, views):
			return p
	var drawn := perimeter_point(rect, frac)
	GameLog.say("No spot round the house out of its doorways' views; the team starts at %s" % drawn)
	return drawn


## A point at fraction `frac` (0..1, clockwise from the top-left) around the perimeter of `rect`.
func perimeter_point(rect: Rect2, frac: float) -> Vector2:
	var d := frac * 4.0  # Four equal sides.
	if d < 1.0:
		return Vector2(lerpf(rect.position.x, rect.end.x, d), rect.position.y)          # top
	elif d < 2.0:
		return Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, d - 1.0))         # right
	elif d < 3.0:
		return Vector2(lerpf(rect.end.x, rect.position.x, d - 2.0), rect.end.y)         # bottom
	return Vector2(rect.position.x, lerpf(rect.end.y, rect.position.y, d - 3.0))        # left


## The node name for NPC `index` of a kind: the plain base for the first (so existing tooling that
## addresses "Defender"/"Invader" keeps working), then "<base> 2", "<base> 3", … for the rest.
func npc_name(base: String, index: int) -> String:
	return base if index == 0 else "%s %d" % [base, index + 1]


## Instance an NPC scene named `node_name` at `pos`, hand its controller the house's rooms, its
## `openings` and optional entry point (`MatchBuilder.bind_npc`, before it joins the tree), and
## record it as a combatant (for the spectator camera + match HUD). It joins the `World` node;
## `MatchBuilder.arm` gives it its weapon afterwards. It is positioned BEFORE it joins the tree: a
## body added at the world origin and moved afterwards overlaps whatever stands there for a moment,
## and the physics launches that piece (or the NPC) across the map.
func add_npc(
	scene: PackedScene,
	node_name: String,
	pos: Vector2,
	rooms: Array,
	entry_point: Vector2 = Vector2.ZERO,
) -> void:
	var npc := scene.instantiate()
	npc.name = node_name
	npc.position = world.to_local(pos)
	MatchBuilder.bind_npc(npc, rooms, openings, entry_point)
	world.add_child(npc)
	combatants.append(npc)
