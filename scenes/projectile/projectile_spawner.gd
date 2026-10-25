class_name ProjectileSpawner
## Projectile System: the one place a bullet is built. Guns (Items) call `spawn`; the bullet
## (projectile.gd) owns its flight and the ballistic outcome of everything it strikes.

const Projectile = preload("res://scenes/projectile/projectile.gd")
const ProjectileVisuals = preload("res://scenes/projectile/projectile_visuals.gd")


## Spawn a bullet at `position` travelling along `direction` into `parent` (the world root), flying
## as `shot` says (its shooter, damage, speed, power and range; null = a plain round, every field
## its default). Returns the node so the caller can connect its `hit` signal.
static func spawn(position: Vector2, direction: Vector2, parent: Node, shot: Shot = null) -> Node:
	if shot == null:
		shot = Shot.new()
	var proj := Node2D.new()
	proj.name = "Projectile"
	proj.script = Projectile
	proj.position = position
	proj.direction = direction
	proj.ignore = shot.shooter
	proj.strikes_shooter = shot.strikes_shooter
	if shot.max_range > 0.0:
		proj.max_distance = shot.max_range
	proj.muzzle_speed = (shot.muzzle_speed
			if shot.muzzle_speed > 0.0
			else BallisticsConfig.projectile_speed)
	proj.speed = proj.muzzle_speed
	proj.penetration_power = maxf(shot.penetration, 0.05)
	proj.damage += shot.item_damage

	var visuals := Node2D.new()
	visuals.name = "ProjectileVisuals"
	visuals.script = ProjectileVisuals
	proj.add_child(visuals)

	# a readable name (Projectile, Projectile2, ...) for the tests and the log
	parent.add_child(proj, true)
	return proj
