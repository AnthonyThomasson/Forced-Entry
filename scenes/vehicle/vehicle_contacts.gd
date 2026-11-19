class_name VehicleContacts extends RefCounted
## Vehicles domain: a vehicle's contacts (`docs/vehicles.md` V6), its body's private `_contacts`
## part: `remember` from the 3D body's `_integrate_forces` after the drive's step, `read` and
## `apply` in the vehicle's `_physics_process`. The closing speeds, the crashes, the dead bodies
## rolled over, the piles of characters shoved and the characters hurt. What the vehicle touches is
## found by a shape query of its body in the twin space (never by Jolt's contact events: they arrive
## in a different count and order run to run), the others in a fixed order (by where they stand).
## Built once with its vehicle (the 2D body); it holds the vehicle (a node, so no reference cycle)
## for its mass, its 3D body, its physics space, its row's `bounce`, its collision exceptions and
## its `post`.

## How near (px) a body is to the vehicle's for the vehicle to be touching it, and how many bodies
## it reads at once.
const TOUCH_MARGIN := 1.5
const TOUCH_HITS := 12

## The vehicle it belongs to.
var vehicle: Node2D
## The velocities the last physics step began with: what an impact found this step was struck at.
var _last_velocity := Vector2.ZERO
var _last_spin := 0.0
## The bodies touching the vehicle at the last step (instance id -> true), to tell a new impact from
## a lasting contact.
var _touching: Dictionary = {}
## What the contacts found, carried out in `_physics_process` (outside the physics server's flush,
## where a death may change bodies): `{ body, push, harm, position }`, a character or a piece shoved
## by `push` (an impulse) and, for a character newly struck, hurt by the closing speed `harm` (0:
## not hurt).
var _struck: Array = []
## When (the vehicle's own physics clock, s) each living character was last in a pile (instance id
## -> time): one struck again within `rehit_time` is the same run-in, shoved on but not hurt again.
var _piled: Dictionary = {}
## Its own physics clock (s), advanced each step in `remember`.
var _clock := 0.0


func _init(body: Node2D) -> void:
	vehicle = body


## Read the last step's contacts, each body's closing speed taken from the velocities that step
## began with. A body newly struck faster than `crash_min_speed` posts a crash at once (the step
## that stopped the vehicle is the one it is heard in). Furniture alone is left to the physics
## engine, which shoves it; a contact with a living character in its pile (the character itself, or
## a piece pressed against one) goes through `_strike_pile`, and a dead body is rolled over. A
## parked vehicle (asleep) meets nothing new.
func read() -> void:
	var lead := TwinSpace.leader_of(vehicle)
	if lead == null or lead.sleeping:
		_touching = {}
		return
	var touching := {}
	var struck := _strongest_contacts(lead, touching)
	var done := {}  # bodies already met in a pile this step
	for hit: Dictionary in struck:
		if not done.has((hit["body"] as Node).get_instance_id()):
			_meet(lead, hit, done)
	_touching = touching
	for id in _piled.keys():
		if _clock - float(_piled[id]) > VehicleCollisionConfig.rehit_time:
			_piled.erase(id)


## Keep the velocities the drive's step ends with (the 3D body calls this after it): what the next
## step's contacts are struck at, and advance the clock.
func remember(state: PhysicsDirectBodyState3D) -> void:
	_last_velocity = PlanSpace.plan_of(state.linear_velocity)
	_last_spin = -state.angular_velocity.y
	_clock += state.step


## The bodies the vehicle touches now, in a fixed order (where they stand), each with its strongest
## contact: `{ body, speed, position, normal, new }` (`speed` the closing speed along `normal`, out
## of the vehicle into the body; `new` when it was not touching last step). Marks each body met in
## `touching` (instance id -> true). A body the vehicle has a collision exception with (a character
## getting in or out, a corpse) is not touched.
func _strongest_contacts(lead: RigidBody3D, touching: Dictionary) -> Array:
	var space := lead.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = (
		PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_CHARACTER | PhysicsLayers.TWIN_VEHICLE
	)
	query.margin = TOUCH_MARGIN
	var hull := lead.get_child(0) as CollisionShape3D  # its whole outline: the shape at the ground
	query.shape = hull.shape
	query.transform = lead.global_transform * hull.transform
	query.exclude = [lead.get_rid()]
	var near := {}
	for found: Dictionary in space.intersect_shape(query, TOUCH_HITS):
		var body := TwinSpace.owner_of(found["collider"])
		if body is PhysicsBody2D and body != vehicle and not _excepted(body):
			near[body.get_instance_id()] = body
	var bodies: Array = near.values()
	bodies.sort_custom(_nearer_the_origin)
	var out: Array = []
	for body: Node2D in bodies:
		var fresh := not _touching.has(body.get_instance_id())
		var hit := _contact_with(space, query, body, fresh)
		if hit.is_empty():
			continue
		touching[body.get_instance_id()] = true
		hit["new"] = fresh
		out.append(hit)
	return out


## The contact of the vehicle's body (`query`) with `body` alone:
## `{ body, speed, position, normal }`, empty when it is not touching it after all.
func _contact_with(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D,
		body: Node2D, fresh: bool) -> Dictionary:
	var alone := PhysicsShapeQueryParameters3D.new()
	alone.shape = query.shape
	alone.transform = query.transform
	alone.collision_mask = query.collision_mask
	alone.margin = query.margin
	var exclude: Array[RID] = [TwinSpace.leader_of(vehicle).get_rid()]
	for other: Dictionary in space.intersect_shape(query, TOUCH_HITS):
		if TwinSpace.owner_of(other["collider"]) != body:
			exclude.append(other["rid"])
	alone.exclude = exclude
	var rest := space.get_rest_info(alone)
	if rest.is_empty():
		return {}
	var at := PlanSpace.plan_of(rest["point"])
	var normal := PlanSpace.plan_of(rest["normal"]).normalized()
	var offset := at - vehicle.global_position
	if offset.dot(normal) < 0.0:
		normal = -normal  # Out of the vehicle, into the other body.
	var ours := _last_velocity + Vector2(-offset.y, offset.x) * _last_spin
	return {
		"body": body,
		"speed": (ours - _velocity_of(body, fresh)).dot(normal),
		"position": at,
		"normal": normal,
	}


## Whether `body` and the vehicle share space (a collision exception either way): a character
## boarding or just out, a corpse the vehicle rolls over.
func _excepted(body: Node) -> bool:
	return (vehicle as PhysicsBody2D).get_collision_exceptions().has(body) or (
		body as PhysicsBody2D
	).get_collision_exceptions().has(vehicle)


## Bodies in a fixed order: by where they stand (their instance ids differ run to run).
static func _nearer_the_origin(a: Node2D, b: Node2D) -> bool:
	if a.global_position.x != b.global_position.x:
		return a.global_position.x < b.global_position.x
	return a.global_position.y < b.global_position.y


## Meet the body of contact `hit` (one of `_strongest_contacts`): roll over a dead body, strike a
## pile with a living character in it, else post a crash for a new impact. The pile's members go
## into `done`, so none of them is met again this step.
func _meet(lead: RigidBody3D, hit: Dictionary, done: Dictionary) -> void:
	var body: Node = hit["body"]
	var character := _is_character(body)
	var living: bool = character and not body.is_dead
	# A living character is always seen to (the solver may stop the vehicle on it even as it moves
	# off); anything else only while the vehicle closes on it.
	if hit["speed"] <= 0.0 and not living:
		return
	if character and not living:
		_roll_over(lead, hit)
		return
	var pile := _pile(body, hit["normal"]) if character or _is_piece(body) else {}
	for member: Dictionary in pile.get("members", []):
		done[(member["body"] as Node).get_instance_id()] = true
	# a piece pressed against a character stops the vehicle (through the piece) as the character
	# does; a piece with nobody behind it is the physics engine's alone
	if pile.get("people", 0) > 0:
		_strike_pile(lead, hit, pile)
	elif hit["new"] and hit["speed"] > VehicleCollisionConfig.crash_min_speed:
		_post_crash(hit, body, hit["speed"])
		if _is_piece(body):
			_strike_piece(hit)


## The blow of the vehicle's bumper on the piece of `hit`: `strike_share` of the closing speed times
## its mass, along the contact, at the bumper's height (carried out in `apply`).
func _strike_piece(hit: Dictionary) -> void:
	var body: Node2D = hit["body"]
	var speed: float = hit["speed"]
	_struck.append({
		"body": body,
		"push": (hit["normal"] as Vector2) * float(body.get_mass()) * speed
				* VehicleCollisionConfig.strike_share,
		"harm": 0.0,
		"position": hit["position"],
		"height": VehicleCollisionConfig.strike_height(vehicle.kind),
	})


## A dead body is rolled over: the vehicle keeps its speed along the contact `hit` and stops
## colliding with it.
func _roll_over(lead: RigidBody3D, hit: Dictionary) -> void:
	var normal: Vector2 = hit["normal"]
	_keep_along(lead, normal, _last_velocity.dot(normal))
	_struck.append({
		"body": hit["body"],
		"push": Vector2.ZERO,
		"harm": 0.0,
		"position": hit["position"],
	})


## Put the vehicle's velocity along `normal` at `along` (px/s), what it has across the normal left
## as it is: the physics engine's stop on a character is undone this way.
func _keep_along(lead: RigidBody3D, normal: Vector2, along: float) -> void:
	var now: Vector2 = lead.call(&"plan_velocity")
	lead.call(&"set_plan_velocity", now + normal * (along - now.dot(normal)))


## Post a crash at contact `hit` against `against` (its surface's material, `""` for a wall or none)
## at the closing speed `closing`.
func _post_crash(hit: Dictionary, against: Node, closing: float) -> void:
	var surface: Dictionary = against.get_surface() if against.has_method("get_surface") else {}
	vehicle.post(
		&"crash",
		hit["position"],
		{ "speed": closing, "material": String(surface.get("material", "")) },
	)


## Strike the pile `hit` heads (one with a living character in it). The solver treats a character as
## immovable, so it has stopped the vehicle (and any piece pressing one) against it as against a
## wall. Where nothing solid stands behind the pile, that stop is undone: the vehicle and the pile
## meet as two bodies (`_shove_pile`), so the vehicle loses only the momentum the pile takes, and
## each member is shoved up to the pile's new speed. Pinned against a wall (or anything else not
## pushable), the vehicle stops as on a wall and posts a crash. Each living character newly in the
## pile is hurt (`_harm_pile`).
func _strike_pile(lead: RigidBody3D, hit: Dictionary, pile: Dictionary) -> void:
	var normal: Vector2 = hit["normal"]
	var members: Array = pile["members"]
	# How fast the pile moves along the contact: its slowest member, each at its own velocity (a
	# character's what it moves at by itself, its walk and knockback: pressed against the vehicle it
	# may be held back a frame).
	var pile_speed := INF
	for member: Dictionary in members:
		pile_speed = minf(pile_speed, _along(member, normal))
	var offset: Vector2 = hit["position"] - vehicle.global_position
	var ours := (_last_velocity + Vector2(-offset.y, offset.x) * _last_spin).dot(normal)
	var closing := ours - pile_speed
	if closing <= 0.0:
		# The pile moves off at least as fast: the vehicle keeps what it had along the contact.
		if pile["blocked"] == null:
			_keep_along(lead, normal, _last_velocity.dot(normal))
		return
	if pile["blocked"] != null:
		# Pinned: the vehicle stops as the solver stopped it, as on a wall.
		if hit["new"] and closing > VehicleCollisionConfig.crash_min_speed:
			_post_crash(hit, pile["blocked"], closing)
	else:
		_shove_pile(lead, hit, members, closing, pile_speed)
	_harm_pile(members, closing)


## The vehicle and the free pile `members` at contact `hit` meet as two bodies, closing at `closing`
## while the pile moves at `pile_speed` along the contact: the pile's mass all its members', with
## the character's bounce `harm_bounce` on a first touch by a character, the vehicle's own `bounce`
## by a piece, none while it keeps pushing. The vehicle keeps what the pile does not take, and each
## member slower than the pile's new speed is queued a shove up to it.
func _shove_pile(lead: RigidBody3D, hit: Dictionary, members: Array, closing: float,
		pile_speed: float) -> void:
	var normal: Vector2 = hit["normal"]
	var pile_mass := 0.0
	for member: Dictionary in members:
		pile_mass += member["mass"]
	var bounce := 0.0
	if hit["new"]:
		var first_is_character: bool = (members[0] as Dictionary)["character"]
		bounce = (
			VehicleCollisionConfig.harm_bounce if first_is_character
			else float(vehicle.row["bounce"])
		)
	var mass: float = vehicle.mass
	var impulse: float = (1.0 + bounce) * closing * mass * pile_mass / (mass + pile_mass)
	var along: float = _last_velocity.dot(normal) - impulse / mass
	_keep_along(lead, normal, along)
	var pile_to: float = pile_speed + impulse / pile_mass
	for member: Dictionary in members:
		var moving := _along(member, normal)
		if pile_to > moving:
			_struck.append({
				"body": member["body"],
				"push": normal * member["mass"] * (pile_to - moving),
				"harm": 0.0,
				"position": hit["position"],
			})


## Each living character among the pile `members` newly in a pile (not in one for `rehit_time`) is
## queued a blow by the speed it is struck at: the vehicle's `closing` speed, less what the pieces
## between them took of it (the vehicle and those pieces carrying the blow on as one).
func _harm_pile(members: Array, closing: float) -> void:
	for member: Dictionary in members:
		if not member["character"]:
			continue
		var body: Node = member["body"]
		var id := body.get_instance_id()
		if not _piled.has(id):
			var struck_at: float = (closing * vehicle.mass
					/ (vehicle.mass + float(member["through"])))
			_struck.append({
				"body": body,
				"push": Vector2.ZERO,
				"harm": struck_at,
				"position": body.global_position,
			})
		_piled[id] = _clock


## How fast pile member `member` moves along `normal` by itself: a character its own velocity, a
## piece its rigid body's.
static func _along(member: Dictionary, normal: Vector2) -> float:
	var body: Node = member["body"]
	var velocity: Vector2
	if member["character"]:
		velocity = body.velocity
	elif _is_led(body):
		velocity = TwinSpace.leader_of(body).call(&"plan_velocity")
	else:
		velocity = body.linear_velocity
	return velocity.dot(normal)


## The pile `first` heads along `normal` (out of the vehicle): `first` and the bodies pressed one
## against the next in front of it, found through the characters in it (a character's circle,
## `radius`, moved `pile_gap` on along the normal), up to `pile_depth` of them. Returns
## `{ members: [{ body, mass, character, through }], people, blocked }`: `through` the mass of
## the pieces between the vehicle and that member, `people` the living characters, `blocked` what
## stops the pile (a wall or anything else that is not pushable) or
## null. Furniture pressing furniture is the solver's, so a piece is followed only into the
## characters it presses.
func _pile(first: Node, normal: Vector2) -> Dictionary:
	var members: Array = [
		{
			"body": first,
			"mass": float(first.get_mass()),
			"character": _is_character(first),
			"through": 0.0,
		},
	]
	var exclude: Array[RID] = [vehicle.get_rid(), first.get_rid()]
	var blocked: Node = null
	var i := 0
	while i < members.size() and members.size() < VehicleCollisionConfig.pile_depth:
		var member: Dictionary = members[i]
		i += 1
		var found := _pressed_by(member, normal, exclude)
		if found.get("blocked") != null:
			blocked = found["blocked"]
			break
		var through: float = (member["through"]
				+ (0.0 if member["character"] else float(member["mass"])))
		for body: Node in found.get("bodies", []):
			if members.size() >= VehicleCollisionConfig.pile_depth:
				break
			exclude.append(body.get_rid())
			members.append({
				"body": body,
				"mass": float(body.get_mass()),
				"character": _is_character(body),
				"through": through,
			})
	var people := 0
	for member: Dictionary in members:
		if member["character"]:
			people += 1
	return { "members": members, "people": people, "blocked": blocked }


## What pile member `member` presses into along `normal`: `{ bodies, blocked }`. A character:
## whatever its circle moved `pile_gap` on meets ahead of it (`_pressed_by_character`). A piece: the
## living characters within `pile_reach` of it pressed against it (`_pressing_piece`).
func _pressed_by(member: Dictionary, normal: Vector2, exclude: Array[RID]) -> Dictionary:
	var space := vehicle.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = PhysicsLayers.SOLID
	query.exclude = exclude
	if member["character"]:
		return _pressed_by_character(space, query, member["body"], normal)
	return _pressing_piece(space, query, member["body"], normal)


## What the character `body` presses into along `normal`, swept with `query` (a circle, its
## `exclude` set): what its circle, `radius`, moved `pile_gap` on meets ahead of it: a living
## character within 60° ahead, a pushable piece whose surface faces the push; anything else that
## faces it blocks the pile (`{ blocked }`).
func _pressed_by_character(space: PhysicsDirectSpaceState2D,
		query: PhysicsShapeQueryParameters2D, body: Node2D, normal: Vector2) -> Dictionary:
	var bodies: Array = []
	(query.shape as CircleShape2D).radius = body.radius
	query.transform = Transform2D(
		0.0,
		body.global_position + normal * VehicleCollisionConfig.pile_gap,
	)
	var met := space.intersect_shape(query, 8)
	for result: Dictionary in met:
		var other := result["collider"] as Node2D
		if other == null:
			continue
		if _is_character(other):
			if _alive_ahead(other, body, normal):
				bodies.append(other)
			continue
		if not _faces_push(space, query, met, result, normal):
			continue
		if not _is_piece(other):
			return { "blocked": other }
		bodies.append(other)
	return { "bodies": bodies }


## Whether the character `other` is alive and within 60° ahead of `body` along `normal`.
static func _alive_ahead(other: Node2D, body: Node2D, normal: Vector2) -> bool:
	return (not other.is_dead
			and (other.global_position - body.global_position).normalized().dot(normal) > 0.5)


## The living characters within `pile_reach` of the piece `body` (`query`, a circle, its `exclude`
## set), ahead of it along `normal`, whose circles, moved `pile_gap` back toward it, meet it.
func _pressing_piece(space: PhysicsDirectSpaceState2D, query: PhysicsShapeQueryParameters2D,
		body: Node2D, normal: Vector2) -> Dictionary:
	var bodies: Array = []
	(query.shape as CircleShape2D).radius = VehicleCollisionConfig.pile_reach
	query.transform = Transform2D(0.0, body.global_position)
	for result: Dictionary in space.intersect_shape(query, 16):
		var other := result["collider"] as Node2D
		if (other == null
				or not _is_character(other)
				or other.is_dead
				or (other.global_position - body.global_position).dot(normal) <= 0.0):
			continue
		if _presses(space, other, body, normal):
			bodies.append(other)
	return { "bodies": bodies }


## Whether the character `other`'s circle, moved `pile_gap` back along `normal`, meets `piece`.
func _presses(space: PhysicsDirectSpaceState2D, other: Node2D, piece: Node2D,
		normal: Vector2) -> bool:
	var back := PhysicsShapeQueryParameters2D.new()
	var own := CircleShape2D.new()
	own.radius = other.radius
	back.shape = own
	back.collision_mask = PhysicsLayers.SOLID
	back.transform = Transform2D(
		0.0,
		other.global_position - normal * VehicleCollisionConfig.pile_gap,
	)
	back.exclude = [vehicle.get_rid(), other.get_rid()]
	for touched: Dictionary in space.intersect_shape(back, 8):
		if touched["collider"] == piece:
			return true
	return false


## Whether the body of `result` (one of `met`, what `query` overlaps) faces the push: the nearest
## point of its surface the query's circle meets has its normal against `normal`, so the circle runs
## into it rather than brushing past it.
static func _faces_push(
	space: PhysicsDirectSpaceState2D,
	query: PhysicsShapeQueryParameters2D,
	met: Array,
	result: Dictionary,
	normal: Vector2,
) -> bool:
	var alone := PhysicsShapeQueryParameters2D.new()
	alone.shape = query.shape
	alone.transform = query.transform
	alone.collision_mask = query.collision_mask
	var exclude := query.exclude.duplicate()
	for other: Dictionary in met:
		if other["rid"] != result["rid"]:
			exclude.append(other["rid"])
	alone.exclude = exclude
	var rest := space.get_rest_info(alone)
	return not rest.is_empty() and (rest["normal"] as Vector2).dot(normal) < -0.5


## Carry out what the contacts found: shove each body by its push and hurt each character newly
## struck (posting a bump above `crash_min_speed`; harm from `harm_min_speed`, the whole health at
## `harm_kill_speed`). A dead character is a body on the floor that the vehicle rolls over: it stops
## colliding with it.
func apply() -> void:
	var struck := _struck
	_struck = []
	for hit: Dictionary in struck:
		var body: Node = hit["body"]
		if not is_instance_valid(body):
			continue
		var character := _is_character(body)
		if character and body.is_dead:
			_roll_over_for_good(body)
			continue
		# a piece is a free 3D body the physics engine moves as the vehicle presses it: only the
		# blow of the bumper on one first met is given here, at its height; a character is shoved
		if hit["push"] != Vector2.ZERO:
			var at: Vector2 = (hit["position"] - (body as Node2D).global_position
					if hit.has("height") else Vector2.ZERO)
			Knockback.push(body, hit["push"], at, float(hit.get("height", -1.0)))
		var closing: float = hit["harm"]
		if not character or closing <= 0.0:
			continue
		if closing > VehicleCollisionConfig.crash_min_speed:
			vehicle.post(&"bump_character", hit["position"], { "speed": closing })
		var harm := inverse_lerp(
			VehicleCollisionConfig.harm_min_speed, VehicleCollisionConfig.harm_kill_speed, closing,
		)
		if harm > 0.0:
			body.take_damage(float(body.health) * minf(harm, 1.0))
		if body.is_dead:
			_roll_over_for_good(body)


## The vehicle stops colliding with the dead `body`: it rolls over it.
func _roll_over_for_good(body: Node) -> void:
	(vehicle as PhysicsBody2D).add_collision_exception_with(body)


## How fast `body` moves: a character (a kinematic body: neither its server velocity nor the motion
## that pushed it out of the vehicle is its own) the velocity it moves at by itself, its walk and
## any knockback; a body a free 3D body leads (a piece of furniture, another vehicle) that body's,
## unless it is a piece first met (`fresh`): the step that met it has already carried it along, and
## it lay at rest before; a wall or a door none.
static func _velocity_of(body: Node, fresh: bool) -> Vector2:
	if body is CharacterBody2D:
		return (body as CharacterBody2D).velocity
	if fresh and _is_piece(body):
		return Vector2.ZERO
	var lead := TwinSpace.leader_of(body)
	if lead != null:
		return lead.call(&"plan_velocity")
	return Vector2.ZERO


## Whether `body` is a character (the group `characters`, interface 7).
static func _is_character(body: Node) -> bool:
	return body.is_in_group(&"characters")


## Whether `body` is a piece the vehicle can shove on: a free piece of furniture, the footprint of a
## free 3D body with the pushable contract.
static func _is_piece(body: Node) -> bool:
	return body is RigidBody2D and _is_led(body) and body.has_method("get_mass")


## Whether `body` is the frozen footprint of a piece a free 3D body leads (`TwinSpace.leader_of`).
static func _is_led(body: Object) -> bool:
	return TwinSpace.leader_of(body) != null
