extends RefCounted
## Character PUSH (Character domain): the one shove a character's walking body and its pressing legs
## give a pushable piece. The impulse lands at the point of contact, so the piece's own rigid-body
## torque turns it: a sofa pushed at one end slides and swings about a point near the far end, one
## pushed in the middle of a side just slides. The piece is carried rather than launched: the
## impulse is capped so the CONTACT POINT (the piece's linear velocity plus its spin about the
## centre) is never driven faster along the push than the pusher's pace x
## `CharacterPushConfig.carry_factor`. The cap is worked out with the piece's effective mass at that
## point (its mass and inertia together), so a turning end is held to the same pace as a sliding
## one. A piece with no `linear_velocity` (another character) takes the shove uncapped and ignores
## the point. A piece led by a free 3D body (furniture, `TwinSpace.leader_of`) is capped by that
## body's velocity and turn about up and shoved through `Knockback.push` at `height` px above the
## floor (the pusher's hip, its leg) but no higher than the piece's centre of mass: a push that is
## carried along (walking into a chair, pressing a sofa) slides a piece and turns it about up, it
## does not flip it; what tips a piece is a blow (a punch, a kick, a bullet, a blast:
## `Knockback.push`).


## Shove `piece` (a pushable: `apply_impulse(v, at)` + `get_mass()`) along unit `dir` with up to
## `impulse`, at `contact` (the world point's x and y, and its height above the floor in z: -1 for
## none known), carried at no more than `speed` (px/s, the pusher's pace along `dir`) x
## `CharacterPushConfig.carry_factor`.
static func shove(
	piece: Object, dir: Vector2, impulse: float, contact: Vector3, speed: float,
) -> void:
	var at: Vector2 = Vector2(contact.x, contact.y) - (piece as Node2D).global_position
	var height := contact.z
	var lead := TwinSpace.leader_of(piece)
	if lead != null and height >= 0.0:
		height = minf(height, float(lead.call(&"centre_height")))
	if lead != null or "linear_velocity" in piece:
		impulse = minf(impulse, _carried(piece, lead, dir, at, speed))
	Knockback.push(piece, dir * impulse, at, height)


## The most impulse along `dir` at `at` (px from the origin) that keeps the contact point of `piece`
## (the body `lead` leads, if one does) from being driven faster along `dir` than `speed` x
## `CharacterPushConfig.carry_factor`.
static func _carried(
	piece: Object, lead: Object, dir: Vector2, at: Vector2, speed: float,
) -> float:
	var velocity: Vector2
	var spin: float
	var inverse_inertia: float
	if lead != null:
		# a piece led by a free 3D body: its velocity and its turn about up, as that body has them
		velocity = lead.call(&"plan_velocity")
		spin = lead.call(&"plan_spin")
		inverse_inertia = lead.call(&"inverse_yaw_inertia")
	else:
		velocity = piece.linear_velocity
		spin = piece.angular_velocity
		inverse_inertia = 0.0  # a piece with no 3D body turns by no engine: no turning is counted
	var contact_velocity: Vector2 = velocity + Vector2(-at.y, at.x) * spin
	var gap := maxf(speed * CharacterPushConfig.carry_factor - contact_velocity.dot(dir), 0.0)
	# How fast one unit of impulse at `at` moves that point along `dir`: the slide plus the turn it
	# causes.
	var lever := at.cross(dir)
	return gap / (1.0 / maxf(piece.get_mass(), 0.001) + inverse_inertia * lever * lever)
