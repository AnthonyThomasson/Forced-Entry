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

## Physics layer the reach query tests (General's `PhysicsLayers.SOLID` — walls + solid furniture).
const QUERY_MASK := PhysicsLayers.SOLID

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
## `{ object, specs, gap }` (`gap`: px from its centre to the mouse); empty when nothing is in
## reach. The character's `use` weighs it against a door and a vehicle's door (Space acts on the
## nearest).
func nearest_in_reach() -> Dictionary:
	var best := {}
	var best_gap := INF
	var aim: Vector2 = _character.movement.aim_point
	for entry in _query_reachable():
		var gap: float = entry["object"].global_position.distance_to(aim)
		if gap < best_gap:
			best_gap = gap
			best = { "object": entry["object"], "specs": entry["specs"], "gap": gap }
	return best


## Begin a random valid action of `entry`'s object (an `nearest_in_reach()` entry) when idle.
func begin_random(entry: Dictionary) -> void:
	if not is_busy():
		_begin(entry["specs"].pick_random(), entry["object"])


## Every object within reach that advertises at least one valid action, as `[{ object, specs }]`
## (specs already item-gated). Shared by `nearest_in_reach` and the AI-facing queries.
func _query_reachable() -> Array:
	var center: Vector2 = _character.global_position + _character.facing * front_offset
	var shape := CircleShape2D.new()
	shape.radius = reach
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = QUERY_MASK
	params.exclude = [_character.get_rid()]
	params.transform = Transform2D(0.0, center)

	var out: Array = []
	for result in get_world_2d().direct_space_state.intersect_shape(params, 32):
		var obj: Node = result.collider
		if obj == null or not obj.has_method("get_interactions"):
			continue
		var valid := _valid_specs(obj.get_interactions())
		if not valid.is_empty():
			out.append({ "object": obj, "specs": valid })
	return out


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
