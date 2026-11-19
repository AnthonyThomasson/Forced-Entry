extends RefCounted
## Character BODY sub-domain: the melee strike a punch (character_hands.gd) and a kick
## (character_kick.gd) share. A column is queried in the 3D twin space at the striking point, at the
## height the fist or the foot really is (`MeleeBlow.height`: a kick lands at the shin, a punch at
## the fist, reaching down to the ankle), so a kick reaches a low piece and a fist swings over
## nothing it could land on; each body in it not struck
## yet this swing is shoved through the pushable contract at the contact (`Knockback.push`, at that
## height, so a piece struck high leans and one struck low slides), logged, reported to
## `on_hit(body, damage)` and dealt the damage: by its kind and shove (`take_blow(kind, amount,
## impulse)`) when the body takes a blow by kind (a door), else `take_damage`. A strike never
## deforms; a wall (no `apply_impulse`) takes the damage without moving. The floor is no body to
## strike. Stateless.

## How high (px) a strike's volume starts at the lowest: clear of a floor slab's top.
const FLOOR_CLEAR := 1.0
## Physics layers a strike meets: walls, solid furniture, vehicles and living characters.
const MASK := PhysicsLayers.TWIN_ALL


## Strike every body the `blow`'s column overlaps, but `character` itself and those already in
## `struck` (each one struck is added to it), shoving it by the blow's `impulse` and dealing it its
## `damage`. With `first_only` it stops after the first body.
static func strike(
	character: CollisionObject2D,
	blow: MeleeBlow,
	struck: Dictionary,
	first_only: bool,
	on_hit: Callable,
) -> void:
	for body in _reached(character, blow):
		if struck.has(body):
			continue
		struck[body] = true
		var pushed := body.has_method("apply_impulse")
		if pushed:
			Knockback.push(
				body, blow.impulse, blow.at - (body as Node2D).global_position, blow.height
			)
		GameLog.say("%s hit %s for %.1f damage, push %.0f (%s%s)" % [
			blow.what, body.name, blow.damage, blow.impulse.length(),
			"pushable" if pushed else "fixed", blow.note])
		on_hit.call(body, blow.damage)
		if body.has_method("take_blow"):
			body.take_blow(blow.kind, blow.damage, blow.impulse)
		elif body.has_method("take_damage"):
			body.take_damage(blow.damage)
		if first_only:
			return


## The 2D bodies (not `character`) the `blow`'s column reaches in the twin space: from its lowest
## height up to its radius above the blow's height. A floor, with no body, is none.
static func _reached(character: CollisionObject2D, blow: MeleeBlow) -> Array[Node]:
	var found: Array[Node] = []
	var space := TwinSpace.space_of(character)
	if space == null:
		return found
	var low := maxf(blow.base if blow.base >= 0.0 else blow.height - blow.radius, FLOOR_CLEAR)
	var high := maxf(blow.height + blow.radius, low + blow.radius)
	var column := CylinderShape3D.new()
	column.radius = blow.radius * RenderConfig.unit
	column.height = (high - low) * RenderConfig.unit
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = column
	params.collision_mask = MASK
	var own := TwinSpace.twin_for(character) as CollisionObject3D
	if own != null:
		params.exclude = [own.get_rid()]
	params.transform = Transform3D(Basis(), PlanSpace.lift(blow.at, (low + high) * 0.5))
	for result in space.intersect_shape(params, 8):
		var body := TwinSpace.owner_of(result["collider"]) as Node
		if body != null and body is CollisionObject2D:
			found.append(body)
	return found
