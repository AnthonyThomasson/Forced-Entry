class_name VehicleContacts extends RefCounted
## Vehicles domain: a vehicle's contacts (`docs/vehicles.md` V6), its body's private `_contacts`
## part, which the body steps: `read` in `_integrate_forces` before the drive's step, `remember`
## after it, and `apply` in `_physics_process`. The closing speeds, the crashes, the dead bodies
## rolled over, the piles of characters and furniture shoved and the characters hurt. Built once
## with its body; it holds the body (a node, so no reference cycle) for its mass, its physics space,
## its row's `bounce`, its collision exceptions and its `post`.

## The vehicle it belongs to.
var vehicle: RigidBody2D
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
## Its own physics clock (s), advanced each step in `_integrate_forces`.
var _clock := 0.0


func _init(body: RigidBody2D) -> void:
	vehicle = body


## Read this step's contacts, each body's closing speed taken from the velocities the step began
## with. A body newly struck faster than `crash_min_speed` posts a crash at once (the step that
## stopped the vehicle is the one it is heard in). Furniture alone is left to the solver, which
## shoves it; a contact with a living character in its pile (the character itself, or a piece
## pressed against one) goes through `_strike_pile`, and a dead body is rolled over.
func read(state: PhysicsDirectBodyState2D) -> void:
	var touching := {}
	var struck := _strongest_contacts(state, touching)
	_clock += state.step
	var done := {}  # bodies already met in a pile this step
	for id in struck:
		if not done.has(id):
			_meet(state, struck[id], done)
	_touching = touching
	for id in _piled.keys():
		if _clock - float(_piled[id]) > VehicleCollisionConfig.rehit_time:
			_piled.erase(id)


## Keep the velocities this step ends with (after the drive's step): what the next step's contacts
## are struck at.
func remember(state: PhysicsDirectBodyState2D) -> void:
	_last_velocity = state.linear_velocity
	_last_spin = state.angular_velocity


## This step's contacts on `state`, the strongest with each body: instance id -> `{ body, speed,
## position, normal, new }` (`speed` the closing speed along `normal`, out of the vehicle into the
## body; `new` when it was not touching last step). Marks each body met in `touching`.
func _strongest_contacts(state: PhysicsDirectBodyState2D, touching: Dictionary) -> Dictionary:
	var struck := {}
	for i in state.get_contact_count():
		var body := state.get_contact_collider_object(i) as Node
		if body == null:
			continue
		var at := state.get_contact_local_position(i)
		var normal := state.get_contact_local_normal(i)
		var offset := at - state.transform.origin
		if offset.dot(normal) < 0.0:
			normal = -normal  # Out of the vehicle, into the other body.
		var ours := _last_velocity + Vector2(-offset.y, offset.x) * _last_spin
		var closing := (ours - _velocity_of(body, state, i)).dot(normal)
		var id := body.get_instance_id()
		touching[id] = true
		if not struck.has(id) or closing > struck[id]["speed"]:
			struck[id] = {
				"body": body,
				"speed": closing,
				"position": at,
				"normal": normal,
				"new": not _touching.has(id),
			}
	return struck


## Meet the body of contact `hit` (one of `_strongest_contacts`): roll over a dead body, strike a
## pile with a living character in it, else post a crash for a new impact. The pile's members go
## into `done`, so none of them is met again this step.
func _meet(state: PhysicsDirectBodyState2D, hit: Dictionary, done: Dictionary) -> void:
	var body: Node = hit["body"]
	var character := _is_character(body)
	var living: bool = character and not body.is_dead
	# A living character is always seen to (the solver may stop the vehicle on it even as it moves
	# off); anything else only while the vehicle closes on it.
	if hit["speed"] <= 0.0 and not living:
		return
	if character and not living:
		_roll_over(state, hit)
		return
	var pile := _pile(body, hit["normal"]) if character or _is_piece(body) else {}
	for member: Dictionary in pile.get("members", []):
		done[(member["body"] as Node).get_instance_id()] = true
	if pile.get("people", 0) > 0:
		_strike_pile(state, hit, pile)
	elif hit["new"] and hit["speed"] > VehicleCollisionConfig.crash_min_speed:
		_post_crash(hit, body, hit["speed"])


## A dead body is rolled over: the vehicle keeps its speed along the contact `hit` and stops
## colliding with it.
func _roll_over(state: PhysicsDirectBodyState2D, hit: Dictionary) -> void:
	var normal: Vector2 = hit["normal"]
	state.linear_velocity += (normal
			* (_last_velocity.dot(normal) - state.linear_velocity.dot(normal)))
	_struck.append({
		"body": hit["body"],
		"push": Vector2.ZERO,
		"harm": 0.0,
		"position": hit["position"],
	})


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
func _strike_pile(state: PhysicsDirectBodyState2D, hit: Dictionary, pile: Dictionary) -> void:
	var normal: Vector2 = hit["normal"]
	var members: Array = pile["members"]
	# How fast the pile moves along the contact: its slowest member, each at its own velocity (a
	# character's what it moves at by itself, its walk and knockback: pressed against the vehicle it
	# may be held back a frame).
	var pile_speed := INF
	for member: Dictionary in members:
		pile_speed = minf(pile_speed, _along(member, normal))
	var offset: Vector2 = hit["position"] - state.transform.origin
	var ours := (_last_velocity + Vector2(-offset.y, offset.x) * _last_spin).dot(normal)
	var closing := ours - pile_speed
	if closing <= 0.0:
		# The pile moves off at least as fast: the vehicle keeps what it had along the contact.
		if pile["blocked"] == null:
			state.linear_velocity += (normal
					* (_last_velocity.dot(normal) - state.linear_velocity.dot(normal)))
		return
	if pile["blocked"] != null:
		# Pinned: the vehicle stops as the solver stopped it, as on a wall.
		if hit["new"] and closing > VehicleCollisionConfig.crash_min_speed:
			_post_crash(hit, pile["blocked"], closing)
	else:
		_shove_pile(state, hit, members, closing, pile_speed)
	_harm_pile(members, closing)


## The vehicle and the free pile `members` at contact `hit` meet as two bodies, closing at `closing`
## while the pile moves at `pile_speed` along the contact: the pile's mass all its members', with
## the character's bounce `harm_bounce` on a first touch by a character, the vehicle's own `bounce`
## by a piece, none while it keeps pushing. The vehicle keeps what the pile does not take, and each
## member slower than the pile's new speed is queued a shove up to it.
func _shove_pile(state: PhysicsDirectBodyState2D, hit: Dictionary, members: Array, closing: float,
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
			else float(vehicle.row()["bounce"])
		)
	var impulse := (1.0 + bounce) * closing * vehicle.mass * pile_mass / (vehicle.mass + pile_mass)
	var along := _last_velocity.dot(normal) - impulse / vehicle.mass
	state.linear_velocity += normal * (along - state.linear_velocity.dot(normal))
	var pile_to := pile_speed + impulse / pile_mass
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
	return ((body.velocity if member["character"] else body.linear_velocity) as Vector2).dot(normal)


## The pile `first` heads along `normal` (out of the vehicle): `first` and the bodies pressed one
## against the next in front of it, found through the characters in it (a character's circle,
## `radius`, moved `pile_gap` on along the normal), up to `pile_depth` of them. Returns
## `{ members: [{ body, mass, character, through }], people, blocked }`: `through` the mass of the
## pieces between the vehicle and that member, `people` the living characters, `blocked` what stops
## the pile (a wall or anything else that is not pushable) or null. Furniture pressing furniture is
## the solver's, so a piece is followed only into the characters it presses.
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
			vehicle.add_collision_exception_with(body)
			continue
		if hit["push"] != Vector2.ZERO:
			body.apply_impulse(hit["push"])
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
			vehicle.add_collision_exception_with(body)


## How fast `body` moves at contact `i`: a rigid body's velocity at the point as the physics server
## has it; a character (a kinematic body: neither its server velocity nor the motion that pushed it
## out of the vehicle is its own) the velocity it moves at by itself, its walk and any knockback.
static func _velocity_of(body: Node, state: PhysicsDirectBodyState2D, i: int) -> Vector2:
	if body is CharacterBody2D:
		return (body as CharacterBody2D).velocity
	return state.get_contact_collider_velocity_at_position(i)


## Whether `body` is a character (the group `characters`, interface 7).
static func _is_character(body: Node) -> bool:
	return body.is_in_group(&"characters")


## Whether `body` is a piece the vehicle can shove on: a free rigid body with the pushable contract
## (furniture, another vehicle).
static func _is_piece(body: Node) -> bool:
	return (body is RigidBody2D
			and not (body as RigidBody2D).freeze
			and body.has_method("apply_impulse")
			and body.has_method("get_mass"))
