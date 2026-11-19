class_name Explosion
## Projectile System: the burst of a grenade, called by the thrown grenade (Items) when its fuse
## runs out. `frag` is the frag grenade's blast and fragments, `stun` the stun grenade's flash and
## bang (docs/grenades.md G7 to G12). `at` is the burst point, `world` the world root, `source` the
## thrower (null when gone) and `row` the grenade's `GrenadeConfig` row. Both post `&"explosion"`
## `{ position, height, kind, attacker, radius }` (the sound, the camera shake and the AI's
## perception hear it) and call `Physics.spawn_explosion` for its look. A grenade hurts and stuns
## everyone, its thrower and its own side included (G9).
##
## **The blast** reaches every hittable body with a clear line from the burst point within
## `blast_radius`, measured to its centre. The line is the real 3D line in the twin space
## (`TwinSpace`, interface 29) from the burst point (the grenade's centre, at its real altitude: one
## at rest on a desk bursts at the desk's top) to a point of the body at its real height (a
## character's head, chest and hips in its posture, `BodyHeights.sight_points`: any one clear
## reaches it; a piece's middle): a wall, a door, a vehicle or a piece of furniture stops it only
## where it really stands in the way, so a ducked character behind a couch is shielded and a
## standing one right behind it is hit over the back, while one far behind it is in the couch's
## shadow. What it reaches takes `take_hit` and is shoved away. **The fragments** are 3D rays over
## the upper hemisphere from the same point. **The flash** works by sight (the same line to the
## eye, the facing of the victim scaling it); **the bang** by range, through walls at `wall_factor`
## (a wall only: furniture muffles nothing).

const Projectile = preload("res://scenes/projectile/projectile.gd")
## The layer the shape query of the bodies near a burst tests (walls, solid furniture, the living).
const MASK := PhysicsLayers.SOLID
## Most bodies one blast considers: the nearest ones.
const MAX_BODIES := 64
## Most colliders the shape query returns for a blast, before the nearest `MAX_BODIES` are kept
## (a cut made on the engine's order would keep an arbitrary set).
const MAX_FOUND := 4 * MAX_BODIES
## Most twins a line may pass through (the ones that stop it only where it ends, `_walk`) before it
## is called blocked.
const MAX_CLEARED := 8
## A cover reach no piece of furniture is ever within: only the walls stop the line (the bang, G12).
const WALLS_ONLY := -1.0
## The height (px) of a grenade's centre over what it lies on: its radius (3) and the gap it floats
## at (0.5). A burst at `altitude` bursts at `altitude + BURST_CENTRE`.
const BURST_CENTRE := 3.5
## The most a fragment may climb (the sine of its elevation): a fragment never flies exactly up.
const MAX_ELEVATION_SINE := 0.999
## The height (px) past which a fragment is spent: nothing taller than the walls (96) is left to
## strike (no fragment strikes a roof by design: `TWIN_ROOF` is in no line layer), so a steep one
## does not fly its whole reach.
const FRAGMENT_CEILING := 100.0
## The twin layers a line asks: the world and the vehicles, the characters being what it reaches.
const LINE_MASK := SightRay.MASK

## The 3D rays every line refills: the walk from the burst, and the look back from the body.
static var _ray := PhysicsRayQueryParameters3D.new()
static var _back := PhysicsRayQueryParameters3D.new()


## The frag grenade goes off at `at` (plan point), `altitude` px over the floor or over what it lies
## on (`ThrownGrenade.altitude()`): its blast, then its fragments.
static func frag(
	at: Vector2,
	world: Node,
	source: Node,
	row: Dictionary,
	altitude := 0.0,
) -> void:
	var burst := PlanSpace.lift(at, altitude + BURST_CENTRE)
	_announce(burst, &"frag", source, float(row.get("blast_radius", 0.0)))
	Physics.spawn_explosion(world, at, &"frag")
	_blast(burst, world, source, row)
	_fragments(burst, world, source, row)


## The stun grenade goes off at `at`, `altitude` px up: its flash and its bang.
static func stun(
	at: Vector2,
	world: Node,
	source: Node,
	row: Dictionary,
	altitude := 0.0,
) -> void:
	var burst := PlanSpace.lift(at, altitude + BURST_CENTRE)
	_announce(burst, &"stun", source, float(row.get("flash_radius", 0.0)))
	Physics.spawn_explosion(world, at, &"stun")
	var space := TwinSpace.space_of(world)
	var flash_radius := float(row.get("flash_radius", 0.0))
	var bang_radius := float(row.get("bang_radius", 0.0))
	for c: Node2D in _characters(world):
		if _dead(c):
			continue
		var d := at.distance_to(c.global_position)
		if d >= maxf(flash_radius, bang_radius):
			continue
		var cover_reach := float(row.get("flash_cover_reach", INF))
		var seen := not _reach(space, burst, c, cover_reach).is_empty()
		var walled := _reach(space, burst, c, WALLS_ONLY).is_empty()
		var blind := _blind_time(row, c, at, d) if seen else 0.0
		var deaf := (float(row.get("max_deaf", 0.0))
				* clampf(1.0 - d / maxf(bang_radius, 0.01), 0.0, 1.0)
				* (float(row.get("wall_factor", 1.0)) if walled else 1.0))
		c.call("take_stun", blind, deaf)
		if d < float(row.get("point_blank", 0.0)):
			c.call("take_damage", float(row.get("point_blank_damage", 0.0)))


## Post the burst at the 3D point `burst` for whoever listens (the Audio domain, the camera, the
## AI).
static func _announce(burst: Vector3, kind: StringName, source: Node, radius: float) -> void:
	EventBus.post(
		&"explosion",
		{
			"position": PlanSpace.plan_of(burst), "height": PlanSpace.height_of(burst),
			"kind": kind, "attacker": source, "radius": radius,
		},
	)


# --- The frag blast and its fragments (G7, G8) ----------------------------------------------------


## Hurt and shove everything the blast reaches: damage full out to `kill_radius`, falling linearly
## to 0 at `blast_radius`. `burst` is the burst point in the twin space.
static func _blast(burst: Vector3, world: Node, source: Node, row: Dictionary) -> void:
	var radius := float(row.get("blast_radius", 0.0))
	var kill := float(row.get("kill_radius", 0.0))
	var at := PlanSpace.plan_of(burst)
	var space2d := (world as Node2D).get_world_2d().direct_space_state
	var space := TwinSpace.space_of(world)
	for body: Node2D in _bodies_near(space2d, at, radius, _characters(world)):
		var d := at.distance_to(body.global_position)
		if d >= radius:
			continue
		var reach := _reach(space, burst, body)
		if reach.is_empty():
			continue
		var strength := clampf((radius - d) / maxf(radius - kill, 0.01), 0.0, 1.0)
		var away := (body.global_position - at).normalized() if d > 0.01 else Vector2.RIGHT
		if not _dead(body) and body.has_method("take_hit"):
			_strike(body, reach, away, float(row.get("blast_damage", 0.0)) * strength, source)
		var shove := float(row.get("blast_impulse", 0.0)) * strength
		# a light body is not thrown faster than the blast's top speed
		if body.has_method("get_mass"):
			shove = minf(
				shove,
				float(body.call("get_mass")) * float(row.get("blast_max_speed", INF)),
			)
		if body.has_method("blast_push"):
			body.call("blast_push", at, shove)
		elif body.has_method("apply_impulse"):
			body.call("apply_impulse", away * shove)


## Hand `body` a blast `HitInfo` of `damage` and post the `&"hit"` the listeners hear (outcome
## `blast`). The hit carries no impact of its own (`speed_factor` 0): the shove of a blast is the
## grenade's `blast_impulse`, applied by the caller; and no height (-1): it strikes the whole body
## (a character's torso armour cuts it).
static func _strike(
	body: Node2D,
	reach: Dictionary,
	away: Vector2,
	damage: float,
	source: Node,
) -> void:
	if damage <= 0.0:
		return
	var info := HitInfo.new()
	info.position = reach["position"]
	info.normal = reach["normal"]
	info.direction = away
	info.damage = damage
	info.speed_factor = 0.0
	info.height = -1.0  # no height: the blast strikes the whole body
	body.call("take_hit", info)
	var surface: Dictionary = body.call("get_surface") if body.has_method("get_surface") else {}
	Projectile.post_hit(body, info, source, &"blast", surface)


## The grenade's fragments: `fragments` bullets from the burst point `burst` over the upper
## hemisphere, evenly round the circle (each jittered within its share of it) and each at its own
## elevation: `sin(elevation) = q^fragment_flatness`, `q` a stratified draw over [0, 1) (one
## fragment in each share of the draws, shuffled over the azimuths), so most fly near level, as a
## shell's fragments do, and a few climb steeply. Low power and fast, spent past `fragment_range`
## (3D px). They strike like any bullet through the real twins (a wall, a piece of furniture at
## its real height, a body in its posture), so a piece lower than their line is cleared and a ducked
## body behind one is shielded, and name the thrower, who is not spared (G9).
static func _fragments(burst: Vector3, world: Node, source: Node, row: Dictionary) -> void:
	var count := int(row.get("fragments", 0))
	if count <= 0:
		return
	var shot := Shot.new()
	shot.shooter = source
	shot.muzzle_speed = float(row.get("fragment_speed", -1.0))
	shot.penetration = float(row.get("fragment_penetration", 1.0))
	shot.strikes_shooter = true
	shot.damage = float(row.get("fragment_damage", 10.0))
	shot.height = PlanSpace.height_of(burst)
	var flatness := float(row.get("fragment_flatness", 1.0))
	var reach := float(row.get("fragment_range", -1.0))
	var rng := WorldRng.of(world)
	var turn := rng.randf() * TAU
	var strata := _shuffled(count, rng)
	for i in count:
		var angle := turn + TAU * (float(i) + rng.randf_range(-0.4, 0.4)) / float(count)
		var share := (float(strata[i]) + rng.randf()) / float(count)
		var sine := minf(pow(share, flatness), MAX_ELEVATION_SINE)
		shot.rise = sine / sqrt(1.0 - sine * sine)
		shot.max_range = _reach_under_ceiling(reach, shot.height, sine)
		ProjectileSpawner.spawn(
			PlanSpace.plan_of(burst), Vector2.from_angle(angle), world, shot
		)


## How far (3D px) a fragment of `reach` (<= 0: none) climbing at elevation `sine` from `height`
## flies before it passes `FRAGMENT_CEILING`: the shorter of the two.
static func _reach_under_ceiling(reach: float, height: float, sine: float) -> float:
	if sine <= 0.0:
		return reach
	var to_ceiling := maxf(FRAGMENT_CEILING - height, 1.0) / sine
	return to_ceiling if reach <= 0.0 else minf(reach, to_ceiling)


## The numbers 0 to `count` - 1 in an order `rng` draws (Fisher-Yates).
static func _shuffled(count: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = range(count)
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = out[i]
		out[i] = out[j]
		out[j] = swap
	return out


# --- The flash (G11) ------------------------------------------------------------------------------


## Seconds `c`, `d` px from the burst at `at`, is blinded by it with a clear line: `max_blind`
## scaled by distance (full inside `flash_full`, linearly less out to `flash_radius`) and by how
## squarely it faces the burst (x1 facing it, x0.6 side-on, x0.25 back to it, linear between).
static func _blind_time(row: Dictionary, c: Node2D, at: Vector2, d: float) -> float:
	var radius := float(row.get("flash_radius", 0.0))
	var full := float(row.get("flash_full", 0.0))
	var reach := clampf((radius - d) / maxf(radius - full, 0.01), 0.0, 1.0)
	var facing: Vector2 = c.get("facing")
	var dot := (facing.normalized().dot((at - c.global_position).normalized())
			if d > 0.5 and facing.length() > 0.0
			else 1.0)
	var share := lerpf(0.6, 1.0, dot) if dot >= 0.0 else lerpf(0.6, 0.25, -dot)
	return float(row.get("max_blind", 0.0)) * reach * share


# --- Lines and who is near ------------------------------------------------------------------------


## Whether `body` is a character that has died (a body with no `is_dead` is not).
static func _dead(body: Object) -> bool:
	return body.get("is_dead") == true


## Every character under `world` (the group `characters`, interface 7; dead ones included), in tree
## order.
static func _characters(world: Node) -> Array:
	var out: Array = []
	for c: Node in world.get_tree().get_nodes_in_group(&"characters"):
		if world.is_ancestor_of(c):
			out.append(c)
	return out


## The bodies a blast of `radius` at `at` may reach: what its circle overlaps on the solid layer
## (furniture, the living, a door; walls are what block it, so they are left out) and the fallen,
## who have left that layer but are still shoved. Each once.
static func _bodies_near(
	space: PhysicsDirectSpaceState2D,
	at: Vector2,
	radius: float,
	characters: Array,
) -> Array:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, at)
	query.collision_mask = MASK
	var out: Array = []
	for found: Dictionary in space.intersect_shape(query, MAX_FOUND):
		var body: Object = found["collider"]
		# a wall is a static body that takes no shove; a door is a driven one that does
		# (`apply_impulse`)
		if (body is StaticBody2D and not body.has_method("apply_impulse")) or out.has(body):
			continue
		if body.has_method("take_hit") or body.has_method("apply_impulse"):
			out.append(body)
	for c: Node2D in characters:
		if _dead(c) and not out.has(c):
			out.append(c)
	# The shape query lists bodies in the order the engine holds them, which follows what the
	# process allocated before: nearest first (then by place) keeps every draw of the world's
	# random stream, and every hit, on the same body whatever the process ran earlier.
	out.sort_custom(func(a: Node2D, b: Node2D) -> bool: return _nearer(a, b, at))
	if out.size() > MAX_BODIES:
		out.resize(MAX_BODIES)
	return out


## Whether `a` stands nearer the burst at `at` than `b` (a tie: the leftmost, then the topmost,
## then the one spawned first: a total order, so the sort never depends on the engine's).
static func _nearer(a: Node2D, b: Node2D, at: Vector2) -> bool:
	var da := a.global_position.distance_squared_to(at)
	var db := b.global_position.distance_squared_to(at)
	if da != db:
		return da < db
	if a.global_position.x != b.global_position.x:
		return a.global_position.x < b.global_position.x
	if a.global_position.y != b.global_position.y:
		return a.global_position.y < b.global_position.y
	return WorldRng.before(a.get_instance_id(), b.get_instance_id())


## Whether something between `burst` (the burst point, a 3D point of the twin space) and a body at
## plan point `p` shields it from a burst there (G7), by `cover`: a wall, a door, a vehicle or a
## piece of furniture that the 3D line from `burst` to every point of the body in its posture
## (`cover.posture`: the head, the chest and the hips at that posture's heights) meets on its way,
## so a piece lower than the line, or one the line rises over, shields nothing; with a finite
## `cover.cover_reach` (a stun's flash, G11) the line is the eye's alone and a piece only counts
## when `p` is within that many px of it on the burst's side. The rule the blast and the flash keep,
## which the AI's perception asks of a grenade (interface 3). A space with no twins shields
## nothing.
static func shields(
	space: PhysicsDirectSpaceState2D,
	burst: Vector3,
	p: Vector2,
	cover: CoverRule,
) -> bool:
	var twins := TwinSpace.space_for(space)
	if twins == null:
		return false
	var heights := (
		PackedFloat32Array([BodyHeights.eye(cover.posture)])
		if cover.cover_reach != INF
		else BodyHeights.sight_points(cover.posture)
	)
	for height in heights:
		if _walk(twins, burst, PlanSpace.lift(p, height), cover.cover_reach, null).is_empty():
			return false
	return true


## The first wall or piece of furniture on the 3D line from `burst` to the point over plan point
## `to` at the chest of a body in `posture`, as its ray hit with a plan `position` (`Vector2`), or
## {} when the line reaches it: where the AI's perception looks for the shadow behind cover
## (interface 3).
static func first_stop(
	space: PhysicsDirectSpaceState2D,
	burst: Vector3,
	to: Vector2,
	posture: StringName,
) -> Dictionary:
	var twins := TwinSpace.space_for(space)
	if twins == null:
		return {}
	var chest := BodyHeights.sight_points(posture)[1]
	var found := _walk(twins, burst, PlanSpace.lift(to, chest), INF, null)
	if found.is_empty() or found.has("exhausted"):
		return {}
	var out := found.duplicate()
	out["position"] = PlanSpace.plan_of(found["position"])
	return out


## Where the line from the burst point `burst` meets `body`, `{ position, normal }` (plan), or {}
## when something stops it before each point of the body: a wall, a door, a vehicle or a piece of
## furniture on the 3D line (`_walk`) to the body's points, the first clear one reaching it. A
## character's points are its head, chest and hips in its posture (`BodyHeights.sight_points`; its
## eye alone for a flash, a finite `cover_reach`), a piece's its middle, a fallen body's the floor.
## The other characters stop nothing (they are not in the lines' layers). With a finite
## `cover_reach` (the flash, G11) a piece of furniture only stops the line when `body` is within
## that many px of it on the burst's side; at `WALLS_ONLY` (the bang, G12) furniture does not stop
## it at all.
static func _reach(
	space: PhysicsDirectSpaceState3D,
	burst: Vector3,
	body: Node2D,
	cover_reach := INF,
) -> Dictionary:
	var from := PlanSpace.plan_of(burst)
	var outward := (body.global_position - from).normalized()
	if space == null:
		return { "position": body.global_position, "normal": -outward }
	for height in _points(body, cover_reach):
		var found := _walk(
			space, burst, PlanSpace.lift(body.global_position, height), cover_reach, body
		)
		if found.is_empty():
			return { "position": body.global_position, "normal": -outward }
		if TwinSpace.owner_of(found["collider"]) == body:
			var n: Vector3 = found["normal"]
			var flat := Vector2(n.x, n.z)
			return {
				"position": PlanSpace.plan_of(found["position"]),
				"normal": flat.normalized() if flat.length() > 0.001 else -outward,
			}
	return {}


## The heights (px) a line from a burst reaches `body` at: a living character's body points at its
## posture (its eye alone when `cover_reach` is a flash's: it is seen), a piece's middle, a fallen
## body's the floor (`SightRay.target_heights`).
static func _points(body: Node2D, cover_reach: float) -> PackedFloat32Array:
	if _dead(body):
		return PackedFloat32Array([SightRay.GROUND_POINT])
	if cover_reach != INF and cover_reach != WALLS_ONLY and body.get("movement") != null:
		return PackedFloat32Array([SightRay.eye_of(body)])
	return SightRay.target_heights(body)


## Walk the 3D line from `from` to `to` through the twin space and return the ray hit that ends it:
## `target`'s own twin when the line meets it, else the first wall (a static body, a door among
## them) or twin with no body, a piece of furniture or a vehicle (`_against`: with a finite
## `cover_reach` only when `to` is within that many px of the face of it nearest `to`; at
## `WALLS_ONLY` never).
## A floor's slab is looked through. {} when the line is clear, and `{ exhausted = true }`
## (stopped) once it has passed `MAX_CLEARED` twins that did not stop it.
static func _walk(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	cover_reach: float,
	target: Object,
) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = LINE_MASK
	var skip: Array[RID] = []
	for _i in MAX_CLEARED:
		_ray.exclude = skip
		var found := space.intersect_ray(_ray)
		if found.is_empty():
			return {}
		var owner := TwinSpace.owner_of(found["collider"])
		if owner == null or owner == target or owner is StaticBody2D:
			return found
		if (owner is PhysicsBody2D
				and cover_reach != WALLS_ONLY
				and _against(space, from, to, found, cover_reach)):
			return found
		skip.append(found["rid"])
	return { "exhausted": true }


## Whether the line's end `to` is within `cover_reach` px (plan) of the face of the piece `found` it
## meets that lies nearest `to`: the ray back from `to` toward `from` meets that piece first
## (nothing else between) and does so that near `to` (any distance for INF). A body hunched against
## the far side of a couch has the couch's face at its own; one standing back from it has the light
## come round and over.
static func _against(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	found: Dictionary,
	cover_reach: float,
) -> bool:
	if cover_reach == INF:
		return true
	_back.from = to
	_back.to = from
	_back.collision_mask = LINE_MASK
	var near := space.intersect_ray(_back)
	return (not near.is_empty()
			and near["collider"] == found["collider"]
			and PlanSpace.plan_of(to).distance_to(PlanSpace.plan_of(near["position"]))
				<= cover_reach)
