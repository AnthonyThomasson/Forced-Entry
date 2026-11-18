extends Node2D
## A bullet: the control layer of the Projectile System. It is a 3D ray in the twin space
## (`TwinSpace`, interface 29): each physics frame it sweeps forward along its 3D travel (the plan
## `direction` and the `rise` that tilts it) from the muzzle's height, and resolves every twin it
## crosses against its 2D owner's surface, so it clears what stands lower than its line and
## ricochets, penetrates or embeds in what it meets (`docs/cover-and-stance.md` H1, H2). It frees
## itself once spent or past `max_distance`. The 3D `ShotLayer` shows it.

## Emitted for each damaging interaction with the dealt damage. A fly-over emits nothing.
signal hit(body: Node, damage: float)

## Within this many px of `max_distance` a bullet counts as having reached it (float slack on the
## clamped last step).
const SPENT_SLACK := 0.01

## Travel speed in px/s.
@export var speed: float = 1600.0
## Distance the bullet may travel before it is spent and frees itself (px); it stops exactly there.
## A grenade's fragments are given a short one (`ProjectileSpawner.spawn`'s `max_range`).
@export var max_distance: float = 2000.0
## Base damage, before the firing item's damage and the per-hit squareness/speed scaling.
@export var damage: float = 10.0
## The twin layers the bullet can hit (`PhysicsLayers.TWIN_*`): walls, furniture, doors, vehicles
## and the living.
@export_flags_3d_physics var collision_mask: int = PhysicsLayers.TWIN_ALL

## The speed it left the muzzle at (px/s): the reference its damage and impact scale against, so a
## weapon's damage is what it deals at full speed, head-on. The spawner sets it with `speed`.
var muzzle_speed: float = BallisticsFlightConfig.projectile_speed
## Power to punch through what it hits (1 = a pistol round): it divides the speed lost to a surface
## and the deflection, and lowers the speed it needs to get through at all.
var penetration_power: float = 1.0
## How high the bullet is now, px above the floor (`BodyHeights`): the muzzle's at the start, then
## what its line gives. It changes as it flies; what stands lower than it clears.
var height := 0.0
## The plan part of its travel, a unit vector (the floor-plan heading); reassigned on ricochet /
## penetration deflection.
var direction := Vector2.RIGHT
## How steeply it climbs: px of height per px of plan travel (negative falls, 0 is level). The 3D
## travel is `(direction, rise)` normalised.
var rise := 0.0
## Body to skip in the sweep (the shooter), and the `attacker` of the hits it posts.
var ignore: Node
## True when the shooter is struck like anyone else (a grenade's fragments hurt its thrower:
## `docs/grenades.md` G9).
var strikes_shooter := false
## Distance travelled so far (3D, px).
var _traveled := 0.0
## Ray query reuse and colliders excluded from further sweeps (penetrated, or the shooter's own),
## so the bullet does not re-hit them. Ricochets are not added: a bounced bullet may strike the same
## surface again.
var _ray := RayQuery.new()
## `_traveled` at the moment the bullet left a body carrying
## `BallisticsPenetrationConfig.blood_material` (a character); -1 = carrying no blood. The next
## non-flesh surface within `blood_carry_distance` of it gets marked.
var _blood_from := -1.0


func _ready() -> void:
	rotation = direction.angle()


## Advance one frame's travel, resolving each collider crossed. Loops rather than casting
## once because a hit can change direction/speed mid-frame; the guard caps a bounce loop.
func _physics_process(delta: float) -> void:
	if _traveled >= max_distance - SPENT_SLACK:
		queue_free()
		return
	var remaining := minf(speed * delta, max_distance - _traveled)
	var guard := 0
	while remaining > 0.0:
		guard += 1
		if guard > 16:
			return

		var from := _point()
		var target := from + _travel() * remaining
		var result := _sweep(from, target)
		if result.is_empty():
			_place(target)
			_traveled += remaining
			remaining = 0.0
		else:
			var advanced := from.distance_to(result.position)
			_place(result.position)  # Snap to the contact point.
			_traveled += advanced
			remaining = maxf(remaining - advanced, 0.0)
			_resolve(result)
			# Nudge just past the contact (along the possibly-new direction) so the
			# next sweep starts clear of this surface.
			_place(_point() + _travel() * 0.5)
			if speed < BallisticsFlightConfig.projectile_min_speed:
				queue_free()
				return

		if _traveled >= max_distance - SPENT_SLACK:
			queue_free()
			return


## How far (px) the bullet still has to fly before its range runs out.
func range_left() -> float:
	return max_distance - _traveled


## Post the world `&"hit"` event for `info` striking `body`, so decoupled listeners (the AI's combat
## awareness, the Audio domain) learn that something was struck, where, and by whom (`attacker`, or
## null). The event also says how the striker met the surface: `outcome` (a bullet's &"ricochet" /
## &"blocked" / &"penetrate", a blast's &"blast"), the struck `surface`'s `material` ("" for a
## wall), the `speed_factor` it hit at and its penetration `power`: the `penetration_power` of the
## bullet that struck (`info.source`), 1 for a striker with none (a blast). The bullets and the
## grenade's blast (`Explosion`) both post through it.
static func post_hit(
	body: Node,
	info: HitInfo,
	attacker: Node,
	outcome: StringName,
	surface: Dictionary,
) -> void:
	var power: Variant = info.source.get(&"penetration_power") if info.source != null else null
	EventBus.post(&"hit", {
		"position": info.position, "victim": body,
		"direction": info.direction, "damage": info.damage,
		"attacker": attacker,
		"outcome": outcome, "material": String(surface.get("material", "")),
		"speed_factor": info.speed_factor, "power": float(power) if power != null else 1.0,
	})


## The bullet's place in the twin space: its plan position at its height.
func _point() -> Vector3:
	return PlanSpace.lift(position, height)


## Put the bullet at twin-space point `at`.
func _place(at: Vector3) -> void:
	position = PlanSpace.plan_of(at)
	height = PlanSpace.height_of(at)


## The unit 3D vector it travels along.
func _travel() -> Vector3:
	return Vector3(direction.x, rise, direction.y).normalized()


## Turn the bullet to travel along unit 3D vector `to` (a ricochet, a deflection): the plan heading
## and the rise follow. A line straight up or down keeps the heading it had.
func _turn_to(to: Vector3) -> void:
	var flat := Vector2(to.x, to.z)
	if flat.length() > 0.0001:
		direction = flat.normalized()
		rise = to.y / flat.length()
	else:
		rise = signf(to.y) * 1.0e4
	rotation = direction.angle()


## Raycast from `from` to `to` through the twin space, skipping the colliders already handled and
## the shooter's own twin. A twin whose body is gone, or the shooter's (unless a fragment may strike
## its thrower), is skipped for good and the cast goes on from the same place.
func _sweep(from: Vector3, to: Vector3) -> Dictionary:
	var space := TwinSpace.space_of(self)
	for _i in 8:
		var result := _ray.sweep(space, from, to, collision_mask)
		if result.is_empty():
			return result
		var body := TwinSpace.owner_of(result.collider)
		if body == null or (body == ignore and not strikes_shooter):
			_ray.exclude.append(result.rid)
			continue
		result["body"] = body
		return result
	return {}


## Pick one outcome for a hit and, when it deals damage, hand the object a HitInfo (the object owns
## the shove/deform/debris). Mutates direction/speed/_ray.exclude and re-emits `hit`. What the line
## meets it strikes, whatever its height: a table under the line is never reached, a wall over it
## is, so cover shelters by being tall enough, not by chance (H1, H2). The ground a falling line
## reaches (a floor has no body) spends it.
func _resolve(result: Dictionary) -> void:
	var body: Node = result.body
	if not body is PhysicsBody2D:
		speed = 0.0
		return
	# Captured before the ricochet branch reassigns `direction`; the shove follows the shot in.
	var incoming := direction
	var travel := _travel()
	var surface := _surface_for(body, incoming, PlanSpace.height_of(result.position))
	var info := _hit_info(result, incoming)
	# Squareness: |travel · normal|, 1 = head-on. A degenerate normal counts as square. A body's
	# wall is straight up, so a character is met on the plan heading alone: pitch does not glance
	# it.
	var n: Vector3 = result.normal
	var squareness := 1.0 if n.length() < 0.001 else absf(travel.dot(n))
	if n.length() >= 0.001 and body.is_in_group(&"characters"):
		squareness = absf(incoming.dot(_plan_normal(n, incoming)))
	# 2. Ricochet off hard material at a glancing angle: reflect at reduced speed/damage.
	# Not excluded — a bounced bullet can strike the same surface again.
	if (float(surface["penetration"]) >= BallisticsRicochetConfig.penetration_bounce_min
			and squareness < BallisticsRicochetConfig.bounce_square_max):
		_ricochet(body, info, squareness, surface, n)
		return

	info.damage = damage * squareness * info.speed_factor
	# 3. Armour (a surface with a `stop_power`, a character's vest or helmet): a round weaker than
	#    it is stopped, deals the impact and embeds; one that beats it is through, penetrates and
	#    strikes what lies under it (`inner_material`, flesh).
	var stop_power := float(surface.get("stop_power", 0.0))
	if stop_power > 0.0:
		if penetration_power * info.speed_factor < stop_power:
			_embed(body, info, "Shot stopped by %s's armour for %.0f damage (%.0f%% square)"
					% [body.name, info.damage, squareness * 100.0], surface)
			return
		surface = surface.merged(
			{ "material": surface.get("inner_material", surface.get("material", "")) },
			true,
		)
	# 4a. Too slow to punch through (a more penetrating round needs less speed): deal the impact and
	# embed (zeroed speed frees the bullet). A round through armour always goes on.
	elif speed < BallisticsPenetrationConfig.min_speed / penetration_power:
		_embed(body, info, "Shot blocked by %s for %.0f damage (%.0f%% square)"
				% [body.name, info.damage, squareness * 100.0], surface)
		return
	_penetrate(result, info, squareness, surface)


## 2. Glance off `body`'s hard `surface`, `squareness` square, off the face `normal` (3D), the round
## reflected at reduced speed and dealing a share of its damage through `info`.
func _ricochet(
	body: Node,
	info: HitInfo,
	squareness: float,
	surface: Dictionary,
	normal: Vector3,
) -> void:
	info.damage = (damage * squareness * info.speed_factor
			* BallisticsRicochetConfig.bounce_damage_retention)
	_turn_to(_travel().bounce(normal.normalized()).normalized())
	speed *= BallisticsRicochetConfig.bounce_speed_retention
	GameLog.say("Shot ricocheted off %s for %.0f damage (%.0f%% square)"
			% [body.name, info.damage, squareness * 100.0])
	info.blood = _take_blood(surface)
	_deal(body, info, &"ricochet", surface)


## 3 / 4a. Stopped in `body` (its armour, or too slow to punch through): `said` logged, the impact
## in `info` dealt and the round embedded (zeroed speed frees the bullet).
func _embed(body: Node, info: HitInfo, said: String, surface: Dictionary) -> void:
	GameLog.say(said)
	speed = 0.0
	info.blood = _take_blood(surface)
	_deal(body, info, &"blocked", surface)


## 4b. Penetrate the body `result` struck: deal the damage in `info`, bleed speed (more when
## glancing, `squareness`, or hard, the `surface`'s penetration), deflect slightly; leaving a body
## (flesh) it carries that body's blood on from the exit.
func _penetrate(result: Dictionary, info: HitInfo, squareness: float, surface: Dictionary) -> void:
	var body: Node = result.body
	var penetration: float = surface["penetration"]
	var loss := clampf(
		(
			(penetration / 100.0)
				* BallisticsPenetrationConfig.penetrate_loss_scale
				* (2.0 - squareness)
				/ penetration_power
		),
		0.0,
		1.0,
	)
	speed *= (1.0 - loss)
	var j := deg_to_rad(BallisticsPenetrationConfig.penetrate_deflect_max_deg * penetration / 100.0
			/ penetration_power)
	var incoming := _travel()
	var rng := WorldRng.of(self)
	_deflect(rng.randf_range(-j, j), rng.randf_range(-j, j))
	_ray.exclude.append(result.rid)
	GameLog.say("Shot penetrated %s for %.0f damage (%.0f%% square)"
			% [body.name, info.damage, squareness * 100.0])
	info.penetrated = true
	info.blood = _take_blood(surface)
	_find_exit(info, result.position, result.rid, incoming)
	_deal(body, info, &"penetrate", surface)
	if StringName(surface.get("material", "")) == BallisticsPenetrationConfig.blood_material:
		_blood_from = (_traveled
				+ (info.exit_position.distance_to(info.position) if info.has_exit else 0.0))


## Swing the travel `side` rad about up and `lift` rad about the axis across it (a penetration's
## scatter, in both axes).
func _deflect(side: float, lift: float) -> void:
	var to := _travel().rotated(Vector3.UP, side)
	var across := to.cross(Vector3.UP)
	if across.length() > 0.0001:
		to = to.rotated(across.normalized(), lift)
	_turn_to(to.normalized())


## The struck object's surface: where the round meets it (`get_surface_at(height, direction)`, a
## character's armour, `at` px up) when it can say, else via get_surface(), or the wall-rating
## fallback for a body that exposes none.
func _surface_for(body: Node, travel: Vector2, at: float) -> Dictionary:
	if body.has_method("get_surface_at"):
		return body.get_surface_at(at, travel)
	if body.has_method("get_surface"):
		return body.get_surface()
	return { "penetration": BallisticsFlightConfig.wall_penetration }


## Build the HitInfo handed to the struck object for one damaging interaction, from the ray
## `result` and the `incoming` heading: its speed factor (the incoming speed relative to this
## round's own muzzle speed: a fast shot hits harder) taken now, and the height it struck at (what
## a body turns into a hit zone); the outcome fills in the damage, whether it penetrated and the
## blood. The contact and the normal are the plan's (the normal's floor part, none for a face that
## looks straight up or down).
func _hit_info(result: Dictionary, incoming: Vector2) -> HitInfo:
	var info := HitInfo.new()
	info.position = PlanSpace.plan_of(result.position)
	info.normal = _plan_normal(result.normal, -direction)
	info.direction = incoming
	info.speed_factor = speed / muzzle_speed if muzzle_speed > 0.0 else 1.0
	info.height = PlanSpace.height_of(result.position)
	info.source = self
	return info


## The floor part of the 3D face normal `n`, unit; `fallback` (a unit heading) for a face that looks
## straight up or down, which has none.
static func _plan_normal(n: Vector3, fallback: Vector2) -> Vector2:
	var flat := Vector2(n.x, n.z)
	return flat.normalized() if flat.length() > 0.001 else fallback


## Blood this bullet hands to a non-flesh surface it strikes (0..1, fading with the distance since
## it left a body) and then has no more of: the first surface takes it all. 0 if it carries none or
## has gone `blood_carry_distance` px. Flesh never takes it (the wound has its own blood).
func _take_blood(surface: Dictionary) -> float:
	var struck := StringName(surface.get("material", ""))
	if _blood_from < 0.0 or struck == BallisticsPenetrationConfig.blood_material:
		return 0.0
	var dist := _traveled - _blood_from
	_blood_from = -1.0
	var reach := BallisticsPenetrationConfig.blood_carry_distance
	return clampf(1.0 - dist / reach, 0.0, 1.0) if reach > 0.0 and dist <= reach else 0.0


## Fill `info`'s exit fields for a bullet that just penetrated `rid` at `entry` travelling along
## `incoming` (the line it came in on, not the one a deflection turned it onto): cast a ray back
## from `exit_probe_distance` px ahead toward the entry, skipping anything else in between, until it
## meets the penetrated collider's far face. Leaves `has_exit` false for a body thicker than the
## probe.
func _find_exit(info: HitInfo, entry: Vector3, rid: RID, incoming: Vector3) -> void:
	if BallisticsPenetrationConfig.exit_probe_distance <= 0.0:
		return
	var space := TwinSpace.space_of(self)
	var from := entry + incoming * BallisticsPenetrationConfig.exit_probe_distance
	var skip := _ray.exclude.duplicate()
	skip.erase(rid)
	for _i in 4:
		var found := _ray.probe(space, from, entry, collision_mask, skip)
		if found.is_empty():
			return
		if found.rid == rid:
			info.has_exit = true
			info.exit_position = PlanSpace.plan_of(found.position)
			info.exit_normal = _plan_normal(found.normal, direction)
			return
		skip.append(found.rid)


## Hand the hit to the object (if hittable), re-emit `hit`, and post the world `&"hit"` event
## (`post_hit`, `attacker` = the shooter, or null) with its `outcome` (&"ricochet" / &"blocked" /
## &"penetrate").
func _deal(body: Node, info: HitInfo, outcome: StringName, surface: Dictionary) -> void:
	if body.has_method("take_hit"):
		body.take_hit(info)
	hit.emit(body, info.damage)
	post_hit(body, info, ignore if is_instance_valid(ignore) else null, outcome, surface)


## One retained ray query per bullet for both its forward sweeps and its exit probes. The exclusion
## list lives here too: forward casts use it directly, while an exit probe still passes its own
## copy.
class RayQuery extends RefCounted:
	## Colliders the forward sweep no longer hits.
	var exclude: Array[RID] = []
	## The reused ray, with the bullet's always-on inside-hit behavior set once.
	var _ray := PhysicsRayQueryParameters3D.new()


	func _init() -> void:
		_ray.hit_from_inside = true


	## Cast the forward sweep with the bullet's exclusions.
	func sweep(
		space: PhysicsDirectSpaceState3D,
		from: Vector3,
		to: Vector3,
		mask: int,
	) -> Dictionary:
		return _cast(space, from, to, mask, exclude)


	## Cast an exit probe with its own evolving exclusion list.
	func probe(
		space: PhysicsDirectSpaceState3D,
		from: Vector3,
		to: Vector3,
		mask: int,
		exclusions: Array[RID],
	) -> Dictionary:
		return _cast(space, from, to, mask, exclusions)


	## Reuse the ray for one cast with the supplied exclusions.
	func _cast(
		space: PhysicsDirectSpaceState3D,
		from: Vector3,
		to: Vector3,
		mask: int,
		exclusions: Array[RID],
	) -> Dictionary:
		_ray.from = from
		_ray.to = to
		_ray.collision_mask = mask
		_ray.exclude = exclusions
		return space.intersect_ray(_ray)
