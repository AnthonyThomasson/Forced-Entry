extends Node2D
## A bullet: the control layer of the Projectile System. Each physics frame it sweeps
## forward along `direction` with a raycast and resolves every collider it crosses against
## that object's surface, so it may fly over cover, ricochet, penetrate, or embed. It frees
## itself once spent or past `max_distance`. Drawing lives in projectile_visuals.gd.

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
## Physics layers the bullet can hit.
@export_flags_2d_physics var collision_mask: int = PhysicsLayers.SOLID
## Streak color.
@export var color: Color = Color(1.0, 0.9, 0.4)
## Streak length in px.
@export var length: float = 7.0

## The speed it left the muzzle at (px/s): the reference its damage and impact scale against, so a
## weapon's damage is what it deals at full speed, head-on. The spawner sets it with `speed`.
var muzzle_speed: float = BallisticsFlightConfig.projectile_speed
## Power to punch through what it hits (1 = a pistol round): it divides the speed lost to a surface
## and the deflection, and lowers the speed it needs to get through at all.
var penetration_power: float = 1.0
## How high the bullet flies, 0..100: the same scale as an object's `coverage` (its height). One
## number for the whole flight, drawn once at spawn (see `BallisticsFlightConfig.bullet_height`), so
## it clears or meets everything it crosses consistently: cover that stands taller than it is
## struck, anything lower is flown over.
var height := 0.0
## Unit travel vector; reassigned on ricochet / penetration deflection.
var direction := Vector2.RIGHT
## Body to skip in the sweep (the shooter), and the `attacker` of the hits it posts.
var ignore: Node
## True when the shooter is struck like anyone else (a grenade's fragments hurt its thrower:
## `docs/grenades.md` G9).
var strikes_shooter := false
## Distance travelled so far.
var _traveled := 0.0
## Colliders excluded from further sweeps (flown over or penetrated), so the bullet does not
## re-hit them. Ricochets are not added — a bounced bullet may strike the same surface again.
var _exclude: Array[RID] = []
## `_traveled` at the moment the bullet left a body carrying
## `BallisticsPenetrationConfig.blood_material` (a character); -1 = carrying no blood. The next
## non-flesh surface within `blood_carry_distance` of it gets marked.
var _blood_from := -1.0


func _ready() -> void:
	rotation = direction.angle()
	height = (BallisticsFlightConfig.bullet_height
			if BallisticsFlightConfig.bullet_height >= 0.0
			else randf() * 100.0)
	if ignore is CollisionObject2D and not strikes_shooter:
		_exclude.append(ignore.get_rid())


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

		var target := position + direction * remaining
		var result := _sweep(target)
		if result.is_empty():
			position = target
			_traveled += remaining
			remaining = 0.0
		else:
			var advanced := position.distance_to(result.position)
			position = result.position  # Snap to the contact point.
			_traveled += advanced
			remaining = maxf(remaining - advanced, 0.0)
			_resolve(result)
			# Nudge just past the contact (along the possibly-new direction) so the
			# next sweep starts clear of this surface.
			position += direction * 0.5
			if speed < BallisticsFlightConfig.projectile_min_speed:
				queue_free()
				return

		if _traveled >= max_distance - SPENT_SLACK:
			queue_free()
			return


## Raycast from the current position to `to`, skipping already-handled colliders.
func _sweep(to: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(position, to, collision_mask)
	query.hit_from_inside = true  # Register even a point-blank shot against a wall.
	query.exclude = _exclude
	return space.intersect_ray(query)


## Pick one outcome for a hit and, when it deals damage, hand the object a HitInfo (the
## object owns the shove/deform/debris). Mutates direction/speed/_exclude and re-emits `hit`.
func _resolve(result: Dictionary) -> void:
	var body: Node = result.collider
	# Captured before the ricochet branch reassigns `direction`; the shove follows the shot in.
	var incoming := direction
	var surface := _surface_for(body, incoming)

	# 1. Fly over cover: the bullet is higher than the object stands. No damage, exclude the body,
	#    keep flying.
	# Coverage is the object's height, so a body behind cover that is taller than the bullet is
	# flown over too: cover 50 and a body of 60 -> a shot lower than 50 meets the cover (and may
	# punch through to the body), one between 50 and 60 clears the cover and strikes only the body,
	# and a higher one misses both.
	if height >= _flyover_height(surface["coverage"]):
		_exclude.append(result.rid)
		GameLog.say("Shot flew over %s" % body.name)
		return

	var info := _hit_info(result, incoming)
	# Squareness: |travel · normal|, 1 = head-on. A degenerate normal counts as square.
	var n: Vector2 = result.normal
	var squareness := 1.0 if n.length() < 0.001 else absf(direction.dot(n))
	# 2. Ricochet off hard material at a glancing angle: reflect at reduced speed/damage.
	# Not excluded — a bounced bullet can strike the same surface again.
	if (float(surface["penetration"]) >= BallisticsRicochetConfig.penetration_bounce_min
			and squareness < BallisticsRicochetConfig.bounce_square_max):
		_ricochet(body, info, squareness, surface)
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


## 2. Glance off `body`'s hard `surface`, `squareness` square, the round reflected at reduced speed
## and dealing a share of its damage through `info`.
func _ricochet(body: Node, info: HitInfo, squareness: float, surface: Dictionary) -> void:
	info.damage = (damage * squareness * info.speed_factor
			* BallisticsRicochetConfig.bounce_damage_retention)
	direction = direction.bounce(info.normal).normalized()
	rotation = direction.angle()
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
	var body: Node = result.collider
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
	direction = direction.rotated(randf_range(-j, j))
	rotation = direction.angle()
	_exclude.append(result.rid)
	GameLog.say("Shot penetrated %s for %.0f damage (%.0f%% square)"
			% [body.name, info.damage, squareness * 100.0])
	info.penetrated = true
	info.blood = _take_blood(surface)
	_find_exit(info, result.position, result.rid, info.direction)
	_deal(body, info, &"penetrate", surface)
	if StringName(surface.get("material", "")) == BallisticsPenetrationConfig.blood_material:
		_blood_from = (_traveled
				+ (info.exit_position.distance_to(result.position) if info.has_exit else 0.0))


## The bullet height at and above which a collider of this `coverage` is flown over: its coverage,
## pushed toward "never" by a `cover_flyover_scale` below 1 (0 = never fly over) and toward "always"
## above it. Coverage 100 stands taller than any bullet.
func _flyover_height(coverage: float) -> float:
	return clampf(
		100.0 - (100.0 - coverage) * BallisticsFlightConfig.cover_flyover_scale,
		0.0,
		100.0,
	)


## The struck object's surface: where the round meets it (`get_surface_at(height, direction)`, a
## character's armour) when it can say, else via get_surface(), or the wall-rating fallback for a
## collider that exposes none.
func _surface_for(body: Node, travel: Vector2) -> Dictionary:
	if body.has_method("get_surface_at"):
		return body.get_surface_at(height, travel)
	if body.has_method("get_surface"):
		return body.get_surface()
	return {
		"coverage": BallisticsFlightConfig.wall_coverage,
		"penetration": BallisticsFlightConfig.wall_penetration,
	}


## Build the HitInfo handed to the struck object for one damaging interaction, from the ray
## `result` and the `incoming` travel: its speed factor (the incoming speed relative to this round's
## own muzzle speed: a fast shot hits harder) taken now; the outcome fills in the damage, whether it
## penetrated and the blood.
func _hit_info(result: Dictionary, incoming: Vector2) -> HitInfo:
	var info := HitInfo.new()
	info.position = result.position
	info.normal = result.normal
	info.direction = incoming
	info.speed_factor = speed / muzzle_speed if muzzle_speed > 0.0 else 1.0
	info.height = height
	info.source = self
	return info


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


## Fill `info`'s exit fields for a bullet that just penetrated `rid` at `entry`: cast a ray back
## from `exit_probe_distance` px ahead toward the entry, skipping anything else in between, until it
## meets the penetrated collider's far face. Leaves `has_exit` false for a body thicker than the
## probe.
func _find_exit(info: HitInfo, entry: Vector2, rid: RID, travel: Vector2) -> void:
	if BallisticsPenetrationConfig.exit_probe_distance <= 0.0:
		return
	var space := get_world_2d().direct_space_state
	var from := entry + travel * BallisticsPenetrationConfig.exit_probe_distance
	var skip := _exclude.duplicate()
	skip.erase(rid)
	for _i in 4:
		var query := PhysicsRayQueryParameters2D.create(from, entry, collision_mask)
		query.hit_from_inside = true
		query.exclude = skip
		var found := space.intersect_ray(query)
		if found.is_empty():
			return
		if found.rid == rid:
			info.has_exit = true
			info.exit_position = found.position
			info.exit_normal = found.normal
			return
		skip.append(found.rid)


## Hand the hit to the object (if hittable), re-emit `hit`, and post a world `&"hit"` event so
## decoupled listeners (the AI's combat awareness) learn that something was struck, where, and by
## whom (`attacker` = the shooter, or null). The event also says how the round met the surface:
## `outcome` (&"ricochet" / &"blocked" / &"penetrate"), the struck `material` ("" for a wall), the
## `speed_factor` it hit at and the round's penetration `power`.
func _deal(body: Node, info: HitInfo, outcome: StringName, surface: Dictionary) -> void:
	if body.has_method("take_hit"):
		body.take_hit(info)
	hit.emit(body, info.damage)
	EventBus.post(&"hit", {
		"position": info.position, "victim": body,
		"direction": info.direction, "damage": info.damage,
		"attacker": ignore if is_instance_valid(ignore) else null,
		"outcome": outcome, "material": String(surface.get("material", "")),
		"speed_factor": info.speed_factor, "power": penetration_power,
	})
