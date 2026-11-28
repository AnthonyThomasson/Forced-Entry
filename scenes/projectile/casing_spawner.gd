class_name CasingSpawner
## Projectile System: the one place a spent casing is built and registered with the Despawner. Guns
## call `spawn` when a round leaves the barrel; the casing (casing.gd) owns its flight.

const Casing = preload("res://scenes/projectile/casing.gd")


## Spawn a spent casing at `position`, `height` px up (the gun's port: the shooter's muzzle;
## negative: a standing one's), ejected to a random side of the firing `direction` (with a slight
## backward kick) into `parent` (the world root), and register it for despawn.
static func spawn(position: Vector2, direction: Vector2, parent: Node, height := -1.0) -> Node:
	var casing := Node2D.new()
	casing.name = "Casing"
	casing.script = Casing
	casing.position = position

	parent.add_child(casing)
	Despawner.track(casing)

	# Eject sideways (random side) plus a small backward component.
	var side := 1.0 if WorldRng.of(parent).randf() > 0.5 else -1.0
	var eject_dir := direction.orthogonal() * side - direction * 0.3
	casing.start(eject_dir, height if height >= 0.0 else BodyHeights.muzzle(BodyHeights.STAND))
	return casing
