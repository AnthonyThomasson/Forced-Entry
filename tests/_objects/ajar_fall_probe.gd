extends RefCounted
## Helper of the ajar-door fall tests (#194, `docs/doors.md` DR11): the gun range's four
## doorways onto the range fitted with a solid door each, ajar at the angle, hinge side and swing
## the test names, knocked down by a kick, and what each leaves of its doorway once it has settled.

const GunRange := preload("res://sandboxes/player_gun_range_sandbox.gd")
const Probe := preload("res://tests/_objects/piece_probe.gd")
## The free gap between a doorway's jambs (px: `DOORWAY` less the walls' 6 px ends each side).
const FREE_GAP := 48.0
## A kick's blow: the damage that fells a solid door and the shove it gives (px/s), at the lock.
const FELLING := 1000.0
const SHOVE := 800.0
## How far (px) past the wall line (the doorways' y is 0) a leaf felled by a blow must lie, at
## least, to have fallen the blow's way and not across the doorway's wall.
const FAR := 8.0
## How far (px) from the leaf's middle a frag goes off, and how high.
const BLAST_AWAY := 40.0
const BLAST_HEIGHT := 42.0
## How far (px) past the wall line, on the landing side, the thing in a falling leaf's way stands
## (a character's middle; a desk's near edge), and how much a desk may be shoved at most.
const PUPPET_PAST := 14.0
const DESK_PAST := 25.0
const DESK_SHOVED := 30.0
## How deep (px) the leaf may rest in the desk it leans on (a resting contact's slop; a leaf carried
## into it is 11 to 18).
const DEEPEST := 2.0
## How far (degrees) a leaf leaning on a desk must lean to be leaning and not standing in the
## doorway, how long (s) a leaf felled has to be asleep, and how far (px) a character it fell on may
## be moved in the 2 s after (a leaf at rest pushes no one).
const REAL_LEAN := 20.0
const ASLEEP_WITHIN := 4.0
const AT_REST_FOR := 2.0
const NO_CREEP := 0.5
## The desk's size (px).
const DESK := Vector2(120.0, 50.0)
## The fewest px of a doorway a leaf leaning on a desk may leave (it may lean there: D18), and the
## most (px) the leaf's drawn middle may move in one physics frame at the start of its fall.
const NO_POP := 12.0
const POP_FRAMES := 10


## The range's layout with door `i` of `material` ajar `angles[i]` degrees, hinged on the side
## `hinges[i]` (-1 the west jamb, 1 the east) and swinging `intos[i]` (UP into its room, DOWN out
## onto the range).
static func doorways(
	angles: Array, hinges: Array, intos: Array, material := "solid"
) -> Array:
	var all: Array = GunRange._doorways()
	for i in angles.size():
		var spec: Dictionary = all[i]["door"]
		var middle: Vector2 = all[i]["pos"]
		spec["material"] = material
		spec["style"] = "panelled"
		spec["angle"] = angles[i]
		spec["hinge"] = middle + Vector2(GunRange.JAMB * float(hinges[i]), 0.0)
		spec["swing_into"] = intos[i]
	return all


## The door of range doorway `i`.
static func door(t: TestContext, i: int) -> Node2D:
	return t.object(StringName(GunRange.RANGE_DOORS[i]["name"]))


## Kick every one of the first `count` range doors down along `along` (UP: from the range, DOWN:
## from the room), let each settle, and check that it leaves its doorway clear.
static func fell_all(t: TestContext, angles: Array, along: Vector2, label: String) -> void:
	var count := angles.size()
	for i in count:
		var leaf = door(t, i)
		leaf.take_blow(&"kick", FELLING, along * SHOVE, 40.0)
	for i in count:
		var leaf = door(t, i)
		if not t.require(leaf.is_down(), "%s door %d is knocked down" % [label, i]):
			return
		await _settles(t, leaf, "door", 10.0)
		t.check(
			leaf.gap() >= FREE_GAP - 1.0,
			"%s door %d (ajar %.0f) leaves the doorway clear (%.0f of %.0f px; top %.0f, lean %.0f)"
				% [label, i, angles[i], leaf.gap(), FREE_GAP, Probe.top(leaf), Probe.lean(leaf)],
		)


## Blow up a frag a doorway's width short of each of the first `count` range doors, on the side
## `sides[i]` names (UP: the range's side of its wall, DOWN: the room's), at its middle's height,
## and check each leaf settles with its doorway clear.
static func blast_all(t: TestContext, angles: Array, sides: Array) -> void:
	for i in angles.size():
		var leaf = door(t, i)
		var row := GrenadeConfig.row(&"frag").duplicate()
		row["fragments"] = 0
		var from: Vector2 = leaf.global_position - (sides[i] as Vector2) * BLAST_AWAY
		Explosion.frag(from, t.world, null, row, BLAST_HEIGHT)
		await t.seconds(0.3)
		if not t.require(leaf.is_down(), "blasted door %d is knocked down" % i):
			return
		await _settles(t, leaf, "door", 10.0)
		t.check(
			leaf.gap() >= FREE_GAP - 1.0,
			(
				"blasted door %d (ajar %.0f, from %s) leaves the doorway clear "
				+ "(%.0f of %.0f px; top %.0f, lean %.0f)"
			) % [i, angles[i], sides[i], leaf.gap(), FREE_GAP, Probe.top(leaf), Probe.lean(leaf)],
		)


## Fell the first `count` range doors ajar at `angles` (each swinging `intos[i]`) with a blow of
## `kind` (`&"kick"` or `&"rifle"`), each from the door's open side (`from_open`) or from its closed
## side: the leaf falls with the blow, so it lies on the far side of the wall line from whoever
## struck it, and leaves its doorway clear.
static func fell_with_the_blow(
	t: TestContext, angles: Array, intos: Array, kind: StringName, from_open: bool
) -> void:
	for i in angles.size():
		var leaf = door(t, i)
		var along: Vector2 = (intos[i] as Vector2) * (-1.0 if from_open else 1.0)
		if kind == &"kick":
			leaf.take_blow(&"kick", FELLING, along * SHOVE, 40.0)
		else:
			leaf.take_hit(_round(leaf.global_position, along))
	for i in angles.size():
		var leaf = door(t, i)
		var along: Vector2 = (intos[i] as Vector2) * (-1.0 if from_open else 1.0)
		var label := "%s door %d (ajar %.0f, struck from %s)" % [
			kind, i, angles[i], "its open side" if from_open else "its closed side",
		]
		if not t.require(leaf.is_down(), "%s is knocked down" % label):
			return
		await _settles(t, leaf, "door", 10.0)
		var lies := Probe.middle(leaf).y * along.y
		t.check(
			lies >= FAR,
			"%s lies on the far side of the wall line (%.0f px past it, wanted %.0f)"
				% [label, lies, FAR],
		)
		t.check(
			leaf.gap() >= FREE_GAP - 1.0,
			"%s leaves the doorway clear (%.0f of %.0f px; top %.0f, lean %.0f)"
				% [label, leaf.gap(), FREE_GAP, Probe.top(leaf), Probe.lean(leaf)],
		)


## A rifle round that fells a door, striking its middle going `along`.
static func _round(at: Vector2, along: Vector2) -> HitInfo:
	var hit := HitInfo.new()
	hit.position = at
	hit.normal = -along
	hit.direction = along
	hit.damage = FELLING
	hit.speed_factor = 1.0
	hit.height = BLAST_HEIGHT
	return hit


## The landing side of door `i` struck from its open side (`from_open`) or its closed side: the
## way the blow goes along the plan (`intos[i]` is the room it swings into).
static func blow_along(intos: Array, i: int, from_open: bool) -> Vector2:
	return (intos[i] as Vector2) * (-1.0 if from_open else 1.0)


## Put a thing in the way of every door's falling leaf: a puppet (`&"puppet"`) 14 px past its
## wall line, or a desk (`&"desk"`) 25 px past it, on the side the blow goes to.
static func in_the_way(
	s: TestSetup, what: StringName, hinges: Array, intos: Array, from_open: bool
) -> void:
	for i in hinges.size():
		var landing := blow_along(intos, i, from_open)
		var x: float = (GunRange._doorways()[i]["pos"] as Vector2).x
		if what == &"puppet":
			# the blow's landing side holds the standing leaf when it comes from the closed side:
			# the character stands by its hinge then, where the leaf is carried too
			var at := x if from_open else x + 36.0 * float(hinges[i])
			s.actor(StringName("way_%d" % i), &"puppet", Vector2(at, PUPPET_PAST * landing.y))
		else:
			var y := (DESK_PAST + 25.0) * landing.y
			s.object(StringName("way_%d" % i), "desk", Vector2(x, y))


## Strike door `i` with a blow of `kind` along `along`.
static func strike(t: TestContext, i: int, kind: StringName, along: Vector2) -> void:
	var leaf = door(t, i)
	if kind == &"kick":
		leaf.take_blow(&"kick", FELLING, along * SHOVE, 40.0)
	else:
		leaf.take_hit(_round(leaf.global_position, along))


## How deep (px) the shapes of the leaf's 3D body are in the 3D bodies of characters now: the
## longest overlap the physics server reports between them.
static func depth_in_characters(leaf: Node2D) -> float:
	var body := Probe.body(leaf)
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = PhysicsLayers.TWIN_CHARACTER
	var deepest := 0.0
	for child in body.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		query.shape = holder.shape
		query.transform = body.global_transform * holder.transform
		var pairs := body.get_world_3d().direct_space_state.collide_shape(query, 16)
		for i in range(0, pairs.size() - 1, 2):
			deepest = maxf(deepest, (pairs[i] - pairs[i + 1]).length() / RenderConfig.unit)
	return deepest


## Fell every ajar range door with a blow while a puppet or a desk is in the way of its leaf, and
## check where each leaf lies: never overlapping the puppet, clear of the doorway or leaning on the
## desk (the desk shoved by no more than `DESK_SHOVED` px).
static func fell_into_the_way(
	t: TestContext, angles: Array, intos: Array, what: StringName, from_open: bool
) -> void:
	var before: Array = []
	for i in angles.size():
		before.append(_way(t, i, what).global_position)
	for i in angles.size():
		strike(t, i, &"kick", blow_along(intos, i, from_open))
	for i in angles.size():
		var leaf = door(t, i)
		var label := "door %d (ajar %.0f, from %s) with a %s in the way" % [
			i, angles[i], "its open side" if from_open else "its closed side", what,
		]
		if not t.require(leaf.is_down(), "%s is knocked down" % label):
			return
		await _settles(t, leaf, label, ASLEEP_WITHIN)
		var thing := _way(t, i, what)
		var moved := thing.global_position.distance_to(before[i])
		if what == &"puppet":
			await _check_puppet(t, leaf, thing, label, blow_along(intos, i, from_open))
		else:
			_check_desk(t, leaf, thing, moved, label)


## The leaf at rest with a character in its way: it does not rest in them, it lies down flat (top
## within `DoorFallConfig.step_over`) and leaves the doorway clear, far side of the wall line: a
## character that stops the carry is shoved and the leaf sent on, so it is let go clear of its
## frame, not held in it (there is no piece for it to lean on: a character is no wall). In the 2 s
## after it is asleep it moves the character no further (`NO_CREEP`) and stays asleep.
static func _check_puppet(
	t: TestContext, leaf: Node2D, puppet: Node2D, label: String, along: Vector2
) -> void:
	var deep := depth_in_characters(leaf)
	t.check(
		deep <= DEEPEST,
		"%s: the leaf does not rest in the character (%.1f px deep)" % [label, deep],
	)
	t.check(
		leaf.gap() >= FREE_GAP - 1.0,
		"%s: the leaf lies clear of the doorway (gap %.0f of %.0f, lean %.0f, top %.0f)"
			% [label, leaf.gap(), FREE_GAP, Probe.lean(leaf), Probe.top(leaf)],
	)
	var top := Probe.top(leaf)
	t.check(
		top <= DoorFallConfig.step_over,
		"%s: the leaf ends flat on the floor (top %.1f of %.0f px)"
			% [label, top, DoorFallConfig.step_over],
	)
	var lies := Probe.middle(leaf).y * along.y
	t.check(
		lies >= FAR,
		"%s: the carry let the leaf go clear of its frame (%.0f px past the wall line, wanted %.0f)"
			% [label, lies, FAR],
	)
	var spot := puppet.global_position
	await t.seconds(AT_REST_FOR)
	var crept := puppet.global_position.distance_to(spot)
	t.check(
		crept <= NO_CREEP,
		"%s: the leaf at rest pushes the character no further (%.1f px in %.0f s)"
			% [label, crept, AT_REST_FOR],
	)
	t.check(Probe.asleep(leaf), "%s: the leaf is still asleep after %.0f s" % [label, AT_REST_FOR])


## The leaf at rest with a desk in its way: clear of the doorway or leaning on the desk, not in the
## desk, and the desk (shoved `moved` px) not bulldozed.
static func _check_desk(
	t: TestContext, leaf: Node2D, desk: Node2D, moved: float, label: String
) -> void:
	var leans: bool = Probe.lean(leaf) >= REAL_LEAN
	t.check(
		leaf.gap() >= FREE_GAP - 1.0 or leans,
		"%s leaves the doorway clear or leans on the desk (gap %.0f, lean %.0f, top %.0f)"
			% [label, leaf.gap(), Probe.lean(leaf), Probe.top(leaf)],
	)
	t.check(moved <= DESK_SHOVED, "%s: the desk is not bulldozed (%.0f px)" % [label, moved])
	var deep := _depth_in(leaf, desk)
	t.check(deep <= DEEPEST, "%s: the leaf is not in the desk (%.1f px deep)" % [label, deep])


## Fell every ajar range door and follow the middle of each leaf frame by frame for its first
## `POP_FRAMES` frames: it is carried, not moved in a jump.
static func fell_without_a_pop(
	t: TestContext, angles: Array, intos: Array, from_open: bool
) -> void:
	var last: Array = []
	var worst: Array = []
	for i in angles.size():
		last.append(_origin(door(t, i)))
		worst.append(0.0)
	for i in angles.size():
		strike(t, i, &"kick", blow_along(intos, i, from_open))
	for _frame in POP_FRAMES:
		await t.frames(1)
		for i in angles.size():
			var now := _origin(door(t, i))
			worst[i] = maxf(worst[i], now.distance_to(last[i]))
			last[i] = now
	for i in angles.size():
		_check_pop(t, i, angles[i], worst[i], from_open)


## The most (`worst`, px) door `i`'s leaf, ajar `angle`, moved in a frame is no jump.
static func _check_pop(
	t: TestContext, i: int, angle: float, worst: float, from_open: bool
) -> void:
	var from := "its open side" if from_open else "its closed side"
	t.check(
		worst <= NO_POP,
		"door %d (ajar %.0f, from %s): the leaf moves %.1f px a frame at most (wanted %.0f)"
			% [i, angle, from, worst, NO_POP],
	)


## Fell every ajar range door and read which way each leaf lies: toward the blow's way along its
## face (`across` signed by the blow), the lean of its top.
static func fell_and_lean(
	t: TestContext, angles: Array, intos: Array, from_open: bool
) -> void:
	var faces: Array = []
	for i in angles.size():
		var leaf = door(t, i)
		faces.append(leaf.global_transform.y.normalized())
		strike(t, i, &"kick", blow_along(intos, i, from_open))
	for i in angles.size():
		var leaf = door(t, i)
		if not t.require(leaf.is_down(), "door %d is knocked down" % i):
			return
		await _settles(t, leaf, "door", 10.0)
		var along := blow_along(intos, i, from_open)
		var face: Vector2 = faces[i]
		var way := face * (1.0 if face.dot(along) >= 0.0 else -1.0)
		var top := PlanSpace.plan_of(Probe.body(leaf).global_transform.basis.y).normalized()
		t.check(
			top.dot(way) >= 0.5,
			"door %d (ajar %.0f): its top lies toward the blow's side of its face (%.2f)"
				% [i, angles[i], top.dot(way)],
		)


## The plan point of the origin of the leaf's 3D body (the drawn door follows it).
static func _origin(leaf: Node2D) -> Vector2:
	return PlanSpace.plan_of(TwinSpace.twin_for(leaf).global_position)


## Wait for the leaf to sleep, `within` s, and check that it did (`label` names the leaf).
static func _settles(t: TestContext, leaf: Node2D, label: String, within: float) -> void:
	var slept: bool = await Probe.settle(t, leaf, within)
	t.check(slept, "%s: the leaf is asleep within %.0f s" % [label, within])


## The thing put in door `i`'s way: a puppet (`what` is `&"puppet"`) or a desk.
static func _way(t: TestContext, i: int, what: StringName) -> Node2D:
	var id := StringName("way_%d" % i)
	return t.actor(id) if what == &"puppet" else t.object(id)


## How deep (px) the shapes of the leaf's 3D body are in the desk `piece` now: the longest overlap
## the physics server reports between them whose desk-side point lies on the desk's footprint.
static func _depth_in(leaf: Node2D, piece: Node2D) -> float:
	var body := Probe.body(leaf)
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = PhysicsLayers.TWIN_WORLD
	query.exclude = [body.get_rid()]
	var footprint := Rect2(piece.global_position - DESK / 2.0, DESK).grow(2.0)
	var deepest := 0.0
	for child in body.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		query.shape = holder.shape
		query.transform = body.global_transform * holder.transform
		var pairs := body.get_world_3d().direct_space_state.collide_shape(query, 16)
		for i in range(0, pairs.size() - 1, 2):
			if footprint.has_point(PlanSpace.plan_of(pairs[i + 1])):
				deepest = maxf(deepest, (pairs[i] - pairs[i + 1]).length() / RenderConfig.unit)
	return deepest
