extends RefCounted
## The match-assembly module's helper (`MatchBuilder.populate`): where and how a match's NPCs are
## placed. Defenders go to a clear spot in a random room, the invader team in one group outside the
## house, beside its front entrance (`spawn_invader_team`); each NPC is handed the house through
## `bind` (the builder's `MatchBuilder.bind_npc`, before it joins the tree), added under the match's
## `World` node and recorded in `combatants` (the spectator camera, the match HUD and the overlays
## observe that list). It knows the NPC scenes and the Navigation domain's `furniture_holes`; the
## placement rules live here so the builder only wires domains.

## The house defender, dropped into one of the generated rooms.
const DEFENDER_SCENE := preload("res://scenes/ai/npc_defender.tscn")
## The house invader, dropped just outside the house. Same AI, different data.
const INVADER_SCENE := preload("res://scenes/ai/npc_invader.tscn")
## Random points tried in a room, after its centre, before `clear_spot` gives up.
const SPAWN_TRIES := 32
## Rings round a group's point (`spawn_invader_team`) tried for a member before it gives up: six
## hold 130 spots.
const GROUP_RINGS := 6
## How far (px) along the house's outside wall from the front entrance's centre the invader
## team's group point stands (`_beside_front_door`): well past the jamb, out of the doorway's
## straight line.
const DOOR_SIDE_OFFSET := 220.0
## How far (px) out from the house's outside wall the invader team's group point stands
## (`_beside_front_door`): across the street from the front wall, which stays in view.
const DOOR_OUT_OFFSET := 120.0

## The match's `World` node the NPCs are added under.
var world: Node2D = null
## Minimum clearance (px) from solid furniture a character is dropped with (twice that from another
## combatant).
var spawn_clearance: float = 20.0
## How far outside the house's bounding box (px) invaders are dropped.
var invader_margin: float = 80.0
## Every NPC placed so far, in spawn order.
var combatants: Array = []
## How an NPC is handed the house (`bind.call(npc)`), called on each one before it joins the tree;
## an invalid Callable (the default) binds nothing.
var bind := Callable()


## Drop defender number `index` at a clear spot (`clear_spot`) in a random room. `rng` is seeded
## from the spec's `seed` so a pinned layout also pins the NPCs. Added after the house, so it draws
## above it. `rooms` is WorldGen.get_rooms(house), already fetched by the caller.
func spawn_defender(rooms: Array, rng: RandomNumberGenerator, index: int) -> void:
	if rooms.is_empty():
		return
	var room: Dictionary = rooms[rng.randi() % rooms.size()]
	add_npc(DEFENDER_SCENE, npc_name("Defender", index), clear_spot(room["rect"], rng))


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
## packed round one point away from and to the side of the front entrance `front` (its opening,
## `{}` when the house has none; `_beside_front_door`: out across the street on one side of the
## doorway, the side drawn from `rng`, so a pinned house seed pins it), or, in a house
## with no front entrance, round one point of the perimeter `invader_margin` px out of the rooms'
## bounding box, drawn from `rng`; or round `around` when given (the human invader's spot, which a
## member then keeps clear of as of any combatant). Each member takes the spot `_group_spot` gives
## it, nearest the point first; beside the front entrance, none in the doorway's straight strip.
func spawn_invader_team(
	rooms: Array,
	rng: RandomNumberGenerator,
	count: int,
	front: Dictionary,
	around := Vector2.INF,
) -> void:
	if rooms.is_empty():
		return
	var bounds := WorldGen.bounds(rooms)
	var centre := around
	var door := {}
	if centre == Vector2.INF:
		door = _front_door(front, rooms)
		if not door.is_empty():
			centre = _beside_front_door(door, rng, bounds)
	if centre == Vector2.INF:
		centre = perimeter_point(bounds.grow(invader_margin), rng.randf())
	var holes := NavBuilder.furniture_holes(world)
	var outside := func(p: Vector2) -> bool:
		return _outdoors(p, rooms, bounds) and not _in_strip(p, door)
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
			_group_spot(centre, holes, taken, outside),
		)


## The front entrance `front` (its opening, `{ pos, width, rooms, outward, ... }`) as the team is
## placed by it: `{ pos, out, width }` (its centre, the way out of its room among `rooms`, the
## opening's `outward` for that room, and its width), or `{}` when there is none.
func _front_door(front: Dictionary, rooms: Array) -> Dictionary:
	if front.is_empty():
		return {}
	var keys: Array = front.get("rooms", [])
	for room: Dictionary in rooms:
		var i := keys.find(room["key"])
		if i >= 0:
			var out: Vector2 = front["outward"][i]
			return { "pos": front["pos"], "out": out, "width": front["width"] }
	return {}


## The invader team's group point away from and to the side of the front entrance `door`
## (`_front_door`): `DOOR_SIDE_OFFSET` px along the house's outside wall from the doorway's centre
## (out of the doorway's straight line) on the side drawn from `rng`, and `DOOR_OUT_OFFSET` px out
## from the wall, facing the house's front; kept within `bounds` (the rooms' bounding box) grown by
## twice `invader_margin` less two `spawn_clearance`, so the first ring stays on the walkable ring
## round the house (`_outdoors`).
func _beside_front_door(door: Dictionary, rng: RandomNumberGenerator, bounds: Rect2) -> Vector2:
	var out: Vector2 = door["out"]
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var point: Vector2 = (
		door["pos"] + out.orthogonal() * side * DOOR_SIDE_OFFSET + out * DOOR_OUT_OFFSET
	)
	var reach := bounds.grow(invader_margin * 2.0 - spawn_clearance * 2.0)
	return point.clamp(reach.position, reach.end)


## The spot nearest `centre` for one more member of a group: `centre` itself, then the points of
## rings twice `spawn_clearance` apart round it (about one per twice `spawn_clearance` along each
## ring), the first that is `outside` (the team's rule: `_outdoors`, and, given a front entrance,
## out of its straight strip, `_in_strip`) and clear of `holes` and `taken` (`is_clear`). `centre`
## when none is.
func _group_spot(centre: Vector2, holes: Array, taken: Array, outside: Callable) -> Vector2:
	var step := spawn_clearance * 2.0
	for ring in GROUP_RINGS + 1:
		var slots := maxi(1, floori(TAU * ring))
		for k in slots:
			var p := centre + Vector2.from_angle(TAU * k / slots) * step * ring
			if outside.call(p) and is_clear(p, holes, taken):
				return p
	GameLog.say("No clear spawn spot round %s; using it" % centre)
	return centre


## Whether `p` stands in the straight strip out of doorway `door` (`_front_door`): within half its
## width of its centre along the wall. False with no `door`.
func _in_strip(p: Vector2, door: Dictionary) -> bool:
	if door.is_empty():
		return false
	var along := (door["out"] as Vector2).orthogonal()
	return absf((p - door["pos"]).dot(along)) <= float(door["width"]) / 2.0


## Whether `p` stands out of every room by `spawn_clearance` and within twice `invader_margin` of
## `bounds` (the rooms' bounding box), on the walkable ring round the house.
func _outdoors(p: Vector2, rooms: Array, bounds: Rect2) -> bool:
	for room in rooms:
		if (room["rect"] as Rect2).grow(spawn_clearance).has_point(p):
			return false
	return p.distance_to(p.clamp(bounds.position, bounds.end)) <= invader_margin * 2.0


## A point at fraction `frac` (0..1, clockwise from the top-left) around the perimeter of `rect`.
func perimeter_point(rect: Rect2, frac: float) -> Vector2:
	var d := frac * 4.0  # Four equal sides.
	if d < 1.0:
		return Vector2(lerpf(rect.position.x, rect.end.x, d), rect.position.y)          # top
	if d < 2.0:
		return Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, d - 1.0))         # right
	if d < 3.0:
		return Vector2(lerpf(rect.end.x, rect.position.x, d - 2.0), rect.end.y)         # bottom
	return Vector2(rect.position.x, lerpf(rect.end.y, rect.position.y, d - 3.0))        # left


## The node name for NPC `index` of a kind: the plain base for the first (so existing tooling that
## addresses "Defender"/"Invader" keeps working), then "<base> 2", "<base> 3", … for the rest.
func npc_name(base: String, index: int) -> String:
	return base if index == 0 else "%s %d" % [base, index + 1]


## Instance an NPC scene named `node_name` at `pos`, hand it the house (`bind`, before it joins the
## tree) and record it as a combatant (for the spectator camera + match HUD). It joins the `World`
## node; `MatchBuilder.arm` gives it its weapon afterwards. It is positioned BEFORE it joins the
## tree: a body added at the world origin and moved afterwards overlaps whatever stands there for a
## moment, and the physics launches that piece (or the NPC) across the map.
func add_npc(scene: PackedScene, node_name: String, pos: Vector2) -> void:
	var npc := scene.instantiate()
	npc.name = node_name
	npc.position = world.to_local(pos)
	if bind.is_valid():
		bind.call(npc)
	world.add_child(npc)
	combatants.append(npc)
