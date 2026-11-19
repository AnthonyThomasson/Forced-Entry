extends Node2D
## Character INTERACTION layer. Owns object interactions end to end: on a request it finds the
## reachable objects that advertise interactions (their `get_interactions()`), keeps only the
## actions whose item gate passes, targets the object nearest the mouse, and starts a random one
## of that object's valid actions — freezing the character in place until the next request ends
## it and returns the character to where it started. A `move_to` action additionally snaps the
## character onto the object and lets the two bodies overlap (a temporary collision exception, so
## sitting/lying puts the character ON the object without either ejecting or shoving the other);
## actions without `move_to` act in place. The character's `use` (`CharacterUse`) weighs
## `nearest_in_reach()` against a door and a vehicle's door and calls `begin_random(entry)` when the
## object is the nearest to the mouse (the player's Space); it forwards `interactions_in_reach()` /
## `interact_with(object, id)` / `end_interaction()` (a controller picking a specific object +
## action) and reads `is_busy()` / `active_label()`; it never learns what an interaction means, so
## this system can be iterated on its own.

## The twin layer the reach query tests (General's `PhysicsLayers.TWIN_WORLD`: walls, furniture,
## doors).
const QUERY_MASK := PhysicsLayers.TWIN_WORLD
## How high (px) above the floor the reach's cylinder starts: clear of a floor slab's top.
const REACH_FROM := 1.0
## How many results a page of the reach query holds (`TwinSpace.intersecting` pages it).
const REACH_HITS := 64

## How far from the body center (px) an object may be and still be reachable.
@export var reach: float = 46.0
## Bias the reach circle this far ahead of the character along its facing (0 = centered on body).
@export var front_offset: float = 0.0

## The active interaction spec, or empty when idle.
var _active: Dictionary = {}
## The object the active interaction belongs to.
var _active_object: Node = null
## Where the character stood when the interaction began; it returns here on exit.
var _return_position := Vector2.ZERO

## Character (CharacterBody2D) — position, aim, inventory.
@onready var _character := get_parent()


## True while an interaction is in progress (the character is locked).
func is_busy() -> bool:
	return not _active.is_empty()


## The active interaction's HUD label, or "" when idle.
func active_label() -> String:
	return _active.get("label", "")


## The active interaction as `{ object, id }` (the object it acts on and its action's id: `lie`,
## `sit`, `hide`, ...), empty when idle. Read by a mesh that shows who lies on a bed.
func active() -> Dictionary:
	if not is_busy():
		return {}
	return { "object": _active_object, "id": _active.get("id", "") }


## The reachable objects and their valid actions, as `[{ object, specs }]` (empty when none in
## range). Lets a controller (an AI) see its options and choose deliberately via `interact_with`.
func interactions_in_reach() -> Array:
	return _query_reachable()


## Begin action `id` on `object` if it is reachable, valid and we are idle; true on success.
## The caller picks both the object and the action (no nearest/random).
func interact_with(object: Node, id: String) -> bool:
	if is_busy():
		return false
	for entry in _query_reachable():
		if entry["object"] != object:
			continue
		for spec in entry["specs"]:
			if spec.get("id", "") == id:
				_begin(spec, object)
				return true
	return false


## End the active interaction, if any (explicit stop).
func end_interaction() -> void:
	if is_busy():
		_end()


## The reachable object (advertising a valid action) nearest the mouse (`movement.aim_point`), as
## `{ object, specs, gap }` (`gap`: px from the mouse to the nearest point of its colliders, 0 with
## the mouse on it; two at one gap go to the one whose centre is nearer); empty when nothing is in
## reach. The character's `use` weighs it against a door and a vehicle (Space acts on the nearest).
func nearest_in_reach() -> Dictionary:
	var best := {}
	var best_gap := INF
	var best_centre := INF
	var aim: Vector2 = _character.movement.aim_point
	for entry in _query_reachable():
		var gap := _gap_to(entry["object"], aim)
		var centre: float = entry["object"].global_position.distance_to(aim)
		if gap < best_gap or (is_equal_approx(gap, best_gap) and centre < best_centre):
			best_gap = gap
			best_centre = centre
			best = { "object": entry["object"], "specs": entry["specs"], "gap": gap }
	return best


## Begin a random valid action of `entry`'s object (an `nearest_in_reach()` entry) when idle.
func begin_random(entry: Dictionary) -> void:
	if not is_busy():
		_begin(entry["specs"].pick_random(), entry["object"])


## Every object within reach that advertises at least one valid action, as `[{ object, specs }]`
## (specs already item-gated), nearest the centre of the reach first. Shared by `nearest_in_reach`
## and the AI-facing queries. The reach is a cylinder of `reach` px round the point ahead of the
## body, from the floor to a standing head, asked of the twin space (interface 29): what stands
## in it is what its 3D bodies fill, a tipped piece by where it lies.
func _query_reachable() -> Array:
	var space := TwinSpace.space_of(self)
	if space == null:
		return []
	var center: Vector2 = _character.global_position + _character.facing * front_offset
	var shape := CylinderShape3D.new()
	shape.radius = reach * RenderConfig.unit
	shape.height = BodyHeights.head_top(BodyHeights.STAND) - REACH_FROM
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = QUERY_MASK
	params.transform = Transform3D(Basis(), PlanSpace.lift(center, REACH_FROM + shape.height * 0.5))
	var seen := {}
	var found: Array[Node2D] = []
	for result: Dictionary in TwinSpace.intersecting(space, params, REACH_HITS):
		var obj := TwinSpace.owner_of(result["collider"])
		if obj != null and not seen.has(obj) and obj.has_method("get_interactions"):
			seen[obj] = true
			found.append(obj)
	found.sort_custom(func(a: Node2D, b: Node2D) -> bool: return _nearer(a, b, center))
	var out: Array = []
	for obj in found:
		var valid := _valid_specs(obj.get_interactions())
		if not valid.is_empty():
			out.append({ "object": obj, "specs": valid })
	return out


## Whether `a` stands nearer `center` than `b`; at one distance the one further up, then further
## left, so the order never follows the engine's.
func _nearer(a: Node2D, b: Node2D, center: Vector2) -> bool:
	var da := a.global_position.distance_squared_to(center)
	var db := b.global_position.distance_squared_to(center)
	if not is_equal_approx(da, db):
		return da < db
	if not is_equal_approx(a.global_position.y, b.global_position.y):
		return a.global_position.y < b.global_position.y
	return a.global_position.x < b.global_position.x


## Keep only the actions whose item gate passes (no `requires_item`, or the character has it).
func _valid_specs(specs: Array) -> Array:
	var out: Array = []
	for spec in specs:
		var needed: int = spec.get("requires_item", 0)
		if needed <= 0 or _character.inventory.has_item(needed):
			out.append(spec)
	return out


## Start an interaction: remember the return spot; for a `move_to` action let the body share
## space with the object (a collision exception, so neither ejects nor shoves the other) and snap
## onto its center. Actions without `move_to` leave the character where it stands.
func _begin(spec: Dictionary, object: Node) -> void:
	_return_position = _character.global_position
	_active = spec
	_active_object = object
	if spec.get("move_to", false):
		# Re-entering the object just left keeps its existing exception.
		if not _character.use.stop_clearing(object):
			_character.add_collision_exception_with(object)
			TwinSpace.share_space(_character, object, true)
		_character.global_position = object.global_position


## End the active interaction. A controller's call runs inside the character's physics step, so the
## actual teardown is deferred to after the step: moving the body and re-enabling its collision
## mid-solve — then having move_and_slide() run the same frame — is what made the physics lurch.
## The character stays frozen (still busy) for this frame; _teardown runs before the next one.
func _end() -> void:
	call_deferred("_teardown")


## Restore the character to its start spot and hand the object off to the character's
## `use.keep_clear_of`, which re-enables collision only once the body has separated from it (so no
## separation kick). Runs outside the physics step (deferred from _end), then clears the busy state.
func _teardown() -> void:
	_character.global_position = _return_position
	if _active_object != null and _active.get("move_to", false):
		_character.use.keep_clear_of(_active_object)
	_active = {}
	_active_object = null


## How far (px) `point` is from the nearest point of `object`'s 3D body, on the plan (0 under a
## shape); its centre's distance when it has none of a shape this knows (a box, a cylinder, a convex
## polygon).
func _gap_to(object: Node2D, point: Vector2) -> float:
	var twin := TwinSpace.twin_for(object)
	var best := INF
	if twin != null:
		for child in twin.find_children("*", "CollisionShape3D", true, false):
			var holder := child as CollisionShape3D
			if not holder.disabled and holder.shape != null:
				best = minf(best, _shape_gap(holder, point))
	return best if best < INF else object.global_position.distance_to(point)


## `point`'s plan distance from the footprint of one shape of a twin.
func _shape_gap(holder: CollisionShape3D, point: Vector2) -> float:
	var shape := holder.shape
	var at := holder.global_transform
	if shape is CylinderShape3D:
		var centre := PlanSpace.plan_of(at.origin)
		return maxf(centre.distance_to(point) - (shape as CylinderShape3D).radius, 0.0)
	var corners := PackedVector2Array()
	if shape is BoxShape3D:
		var half := (shape as BoxShape3D).size * 0.5
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					corners.append(PlanSpace.plan_of(at * (half * Vector3(x, y, z))))
	elif shape is ConvexPolygonShape3D:
		for corner in (shape as ConvexPolygonShape3D).points:
			corners.append(PlanSpace.plan_of(at * corner))
	if corners.is_empty():
		return INF
	var hull := Geometry2D.convex_hull(corners)
	if Geometry2D.is_point_in_polygon(point, hull):
		return 0.0
	var best := INF
	for i in hull.size() - 1:
		var near := Geometry2D.get_closest_point_to_segment(point, hull[i], hull[i + 1])
		best = minf(best, near.distance_to(point))
	return best
