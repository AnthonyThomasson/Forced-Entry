class_name CharacterTwin
extends CharacterBody3D
## Character domain, the 3D body of a character in the twin space (`TwinSpace`, interface 29, #194
## chars3d-a, D13): an upright cylinder on `PhysicsLayers.TWIN_CHARACTER`, the radius of the body's
## circle and the real height of the posture it is in (`BodyHeights`: standing the stature, ducked
## the duck, a ducked body risen over its cover the pose it rose to), so a ray at head height hits
## a standing body and passes over a ducked one. Its wall is straight up (a round meets the body
## square on at any height, as it does the 2D circle: a rounded top would turn a head shot's damage
## down by the slant it strikes).
##
## **It is the truth of where the character stands.** The character's walk (`CharacterMovement`)
## moves this body (`walk`: `move_and_slide` in 3D against the walls, furniture, doors, vehicles
## and the other characters of the twin space) and writes the 2D body from it, so the 2D body (a
## `CharacterBody2D`, the footprint) stands where this one does and everything that still reads 2D
## (the nav, the interaction finding, the AI's 2D queries, the renderer) goes on reading it. A 2D
## body that a script, a door's swing or a ride has moved (its transform is no longer the one this
## wrote) puts this body there instead (`follow`, `adopt`).
##
## **The floor.** The body is locked upright and on the floor (the plan is its only motion: `y` is
## held at 0, its mode is floating so no tipped piece or ledge is a step to climb: a piece is an
## obstacle). Its cylinder's feet stand `FEET` px up, clear of a floor slab's top (0.1 px) and
## of a kerb a road lies below, so no slab is an edge it catches on. A piece of furniture is walked
## into, never over.
##
## **Posture.** The cylinder follows the body's pose; one that would grow into a solid (stand up
## under a shelf, or a piece lying over it: `fits`) is refused where it is asked for
## (`CharacterMovement.set_posture`, the rise). A seated body (the 2D circle disabled) has no
## cylinder, and a dead body's twin is off the layer (the 2D body's own layer is 0).

const Character = preload("res://scenes/character/character.gd")
## The angle (rad) off square within which a wall stops the walk instead of sliding it.
const HEAD_ON := deg_to_rad(3.0)
## How far (px) the walk keeps off what stops it. A hair more than the engine's 0.001: a walker
## pressed on a swinging leaf would overlap it by rounding, but not so much that the engine's
## recovery pushes it off a leaf the width of a step (0.08, the 2D body's, did: the leaf crept on
## after it).
const SAFE_MARGIN := 0.02
## How high the cylinder's feet are above the floor (px): above a floor slab (0.1) and any slab
## edge, below every piece's lowest part.
const FEET := 0.5
## How much slimmer (px) the cylinder `fits` tests is than the body: a body pressed to a wall fits.
const FITS_SLACK := 0.5
## How long (s) an answer of `fits` is kept while the body stands where it was asked: an NPC pinned
## under a shelf asks to stand every tick, and a shelf does not move in a quarter second.
const FITS_KEEP := 0.25

## The character this is the body of.
var _character: Character
## The cylinder and the holder it is in (resized as the posture changes) and the posture now.
var _shape := CylinderShape3D.new()
var _holder := CollisionShape3D.new()
var _posture: StringName = &""
## Whether the cylinder is off (the character rides a vehicle).
var _seated := false
## The 2D transform this last wrote to the body (a different one is a script's move: `follow`).
var _written := Transform2D()
## The body's velocity (plan, px/s) as it moved last frame: what it covered, not what it asked.
var _real := Vector2.ZERO
## The direction (plan, unit) it was walked in last frame, for telling which contact is a push.
var _wanted := Vector2.ZERO
## The last answer `fits` gave per posture: `[where it stood, when, the answer]`.
var _fit := {}


## Add the hook to `space` (a `TwinSpace`).
static func register(space: TwinSpace) -> void:
	space.builders.append(Callable(CharacterTwin, &"build"))


## The twin of `node` if it is a character, else null.
static func build(node: Node2D) -> Node3D:
	if not node is Character:
		return null
	var twin := CharacterTwin.new()
	twin._character = node as Character
	twin.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# a wall met nearly head on (within `HEAD_ON` of square) stops the slide: the engine
	# renormalises what is left to slide, which at a square hit is only its rounding noise, a
	# full-length shove in a random direction. Its default (15 degrees) stops a round body that
	# meets a leaf's end or a corner a few degrees off square, which the 2D body always slid round
	twin.wall_min_slide_angle = HEAD_ON
	twin.safe_margin = SAFE_MARGIN
	twin.collision_layer = PhysicsLayers.TWIN_CHARACTER
	twin.collision_mask = PhysicsLayers.TWIN_ALL
	twin._shape.radius = twin._character.radius * RenderConfig.unit
	twin._holder.shape = twin._shape
	twin.add_child(twin._holder)
	twin._set_posture(twin._character.movement.body_posture())
	return twin


## The twin space's hand-over: this body takes the character's place as the truth, the 2D body its
## footprint.
func take_over(footprint: Node2D) -> void:
	adopt(footprint)


## The twin space's per-frame hook: a 2D body a script moved puts this one there.
func follow(footprint: Node2D) -> void:
	if footprint.global_transform != _written:
		adopt(footprint)


## Stand where the 2D body `footprint` stands, on the floor, at rest.
func adopt(footprint: Node2D) -> void:
	_written = footprint.global_transform
	global_transform = PlanSpace.lift_transform(_written)
	velocity = Vector3.ZERO
	force_update_transform()


## The twin space's per-frame hook: the cylinder follows the posture, and is off while seated.
func twin_update(_body: Node2D) -> void:
	var now: StringName = _character.movement.body_posture()
	if now != _posture:
		_set_posture(now)
	var layer := 0 if _character.is_dead else PhysicsLayers.TWIN_CHARACTER
	if layer != collision_layer:
		collision_layer = layer
	var seated: bool = _character.use.is_riding()
	if seated != _seated:
		_seated = seated
		_holder.disabled = seated


## One frame's walk: move at the plan velocity `wanted` (px/s) for a physics step, slide along what
## stops it, and write the footprint where the body ended. Returns the plan velocity left after the
## slide. A footprint moved since the last frame (a door's nudge, a script) is taken first.
func walk(wanted: Vector2) -> Vector2:
	follow(_character)
	_wanted = wanted.normalized()
	velocity = Vector3(wanted.x, 0.0, wanted.y) * RenderConfig.unit
	move_and_slide()
	global_position.y = 0.0
	_real = Vector2(get_real_velocity().x, get_real_velocity().z) / RenderConfig.unit
	_write()
	return Vector2(velocity.x, velocity.z) / RenderConfig.unit


## Move the body `aside` (plan px) when nothing in the twin space but `clear_of` (a leaf that
## sweeps over it) stands in the way, and write the footprint where it ended: true when it moved,
## false when something stops it (it then stays).
func shift(aside: Vector2, clear_of: PhysicsBody3D) -> bool:
	follow(_character)
	var motion := Vector3(aside.x, 0.0, aside.y) * RenderConfig.unit
	var excepted := get_collision_exceptions().has(clear_of)
	if not excepted:
		add_collision_exception_with(clear_of)
	var free := not test_move(global_transform, motion, null, SAFE_MARGIN)
	if free:
		global_position += motion
		force_update_transform()
		_write()
	if not excepted:
		remove_collision_exception_with(clear_of)
	return free


## The plan velocity (px/s) the body covered last frame.
func real_velocity() -> Vector2:
	return _real


## What the last walk slid into that takes a shove (a pushable: `apply_impulse`): for each contact
## `{ "body": the 2D body of the twin it touched, "normal": plan normal pointing back at this body,
## "at": plan point }`. A wall or a door is no push and is not listed. A contact is where the round
## body touches along its normal (its rim toward what it touched), whatever point of the contact
## patch the engine reports: a shove given there turns a piece as a circle's push does.
func contacts() -> Array[Dictionary]:
	var best := {}
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var other := TwinSpace.owner_of(hit.get_collider())
		var normal := Vector2(hit.get_normal().x, hit.get_normal().z)
		if other == null or not other.has_method(&"apply_impulse"):
			continue
		if normal.length_squared() < 0.0001:
			continue
		normal = normal.normalized()
		# the engine may report one body more than once (the face walked into, then the edge the
		# slide met): the face most squarely in the way is the push (a tie goes to the larger
		# normal, so the order the engine listed them in decides nothing)
		var squareness := -normal.dot(_wanted)
		var seen: Dictionary = best.get(other, {})
		if seen.is_empty() or _squarer(squareness, normal, seen):
			best[other] = { "body": other, "normal": normal, "squareness": squareness }
	var out: Array[Dictionary] = []
	for found: Dictionary in best.values():
		var normal: Vector2 = found["normal"]
		found["at"] = PlanSpace.plan_of(global_position) - normal * _character.radius
		out.append(found)
	# in a fixed order (by where the bodies stand), not the order the engine met them in
	if out.size() > 1:
		out.sort_custom(_nearer_first)
	return out


## Whether a contact face (`squareness`, `normal`) is more in the way than `seen`, the one kept so
## far: squarer, and for an equal one the larger normal (x, then y).
func _squarer(squareness: float, normal: Vector2, seen: Dictionary) -> bool:
	if not is_equal_approx(squareness, seen["squareness"]):
		return squareness > seen["squareness"]
	var kept: Vector2 = seen["normal"]
	return normal.x > kept.x if not is_equal_approx(normal.x, kept.x) else normal.y > kept.y


## Whether contact `a` comes before `b`: the body that stands further up, then further left.
func _nearer_first(a: Dictionary, b: Dictionary) -> bool:
	var at: Vector2 = (a["body"] as Node2D).global_position
	var other: Vector2 = (b["body"] as Node2D).global_position
	return at.y < other.y if not is_equal_approx(at.y, other.y) else at.x < other.x


## Whether the cylinder of `posture` (a `BodyHeights` pose) stands clear of the solids of the world
## and the vehicles here: false when taking that height would grow the body into something (a
## shelf over its head, a piece lying across it).
func fits(posture: StringName) -> bool:
	if not is_inside_tree():
		return true
	var now := GameClock.seconds()
	var here := global_position
	var kept: Array = _fit.get(posture, [])
	if not kept.is_empty() and kept[0] == here and now - float(kept[1]) < FITS_KEEP:
		return kept[2]
	var answer := _fits_now(posture)
	_fit[posture] = [here, now, answer]
	return answer


## `fits`, asked of the twin space now.
func _fits_now(posture: StringName) -> bool:
	var taller := CylinderShape3D.new()
	taller.radius = _shape.radius - FITS_SLACK
	taller.height = _height_of(posture)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = taller
	query.collision_mask = PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_VEHICLE
	query.exclude = [get_rid()]
	query.transform = Transform3D(
		Basis(),
		global_position + Vector3(0.0, FEET + taller.height * 0.5, 0.0),
	)
	var space := TwinSpace.space_of(_character)
	return space == null or space.intersect_shape(query, 1).is_empty()


## Write the 2D body where this body stands.
func _write() -> void:
	var plan := PlanSpace.plan_of(global_position)
	if plan != _character.global_position:
		_character.global_position = plan
	_written = _character.global_transform


## The cylinder's height (px) in `posture`: the head top above the feet.
static func _height_of(posture: StringName) -> float:
	return maxf((BodyHeights.head_top(posture) - FEET) * RenderConfig.unit, 0.01)


## Stand the cylinder to `posture`'s height (a `BodyHeights` pose), its feet `FEET` up.
func _set_posture(posture: StringName) -> void:
	_posture = posture
	_shape.height = _height_of(posture)
	_holder.position = Vector3(0.0, FEET + _shape.height * 0.5, 0.0)
