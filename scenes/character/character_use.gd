class_name CharacterUse extends RefCounted
## What occupies a character's body (`character.gd`'s `use`): an object interaction (sit, lie, …), a
## ride in a vehicle, its use of doors (`doors`), and the collision exceptions they leave behind. It
## composes the Interaction domain's `CharacterInteraction` and the Vehicles domain's
## `CharacterVehicleUse` as children of the character (`attach`, from its `_ready`), and holds the
## ride's pose. What Space acts on, a chair, a door or a vehicle's door, is decided here
## (`interact_target`, `try_interact`). Each physics frame the character steps the ride right after
## its controller (`control`), lets it hold the body still while it lasts or an interaction holds it
## (`hold_frame`), and drops the exceptions of the bodies it has cleared after the move
## (`restore_cleared`); death ends both (`end_interaction`, `abandon`).

## Extra gap (px) around the body before the collision with a body it left (`keep_clear_of`) is
## restored.
const CLEAR_MARGIN := 3.0
## How high (px) the overlap test's cylinder starts: clear of a floor slab's top.
const CLEAR_FROM := 1.0
## How many results a page of the overlap test holds (`TwinSpace.intersecting` pages it).
const CLEAR_HITS := 64
## Interaction component (Interaction domain): finds and runs object interactions;
## `nearest_in_reach`, `is_busy()` and `interaction_label()` go through it.
const CharacterInteraction = preload("res://scenes/interaction/character_interaction.gd")
## Vehicle component (Vehicles domain): boards, rides and leaves vehicles; `try_interact()` (when a
## vehicle is what Space acts on), `vehicle()` and `is_in_vehicle()` go through it, and it drives
## the ride each frame (`control`).
const CharacterVehicleUse = preload("res://scenes/vehicle/character_vehicle_use.gd")

## The character occupied.
var character: CharacterBody2D
## Its use of doors (`character_doors.gd`): the door in reach, working it.
var doors: CharacterDoors
## The CharacterInteraction child, built by `attach()`.
var _interaction: Node
## The CharacterVehicleUse child, built by `attach()`.
var _vehicle_use: Node
## A ride in a vehicle (the Vehicles domain moves the character through `set_ride_pose` /
## `end_ride`): posed by it rather than walking, its collision shape off, its held item put away;
## the step its legs take through the vehicle.
var _riding := false
var _ride_step := Vector2.ZERO
## The bodies just left (an interaction's object, a vehicle) whose collision exception waits for the
## body to clear them.
var _clearing: Array = []  # untyped: a body freed while waiting stays in it until the next check
## The character's collision circle, off while it rides.
var _shape: CollisionShape2D


## What occupies `host`.
func _init(host: CharacterBody2D) -> void:
	character = host
	doors = CharacterDoors.new(host)


## Add the interaction and the vehicle use as children of the character (from its `_ready`).
func attach() -> void:
	_shape = character.get_node(^"CollisionShape2D")
	_interaction = CharacterInteraction.new()
	character.add_child(_interaction)
	_vehicle_use = CharacterVehicleUse.new()
	character.add_child(_vehicle_use)


## What Space acts on now, as `{ kind, object }` (empty when nothing is, or the character is dead):
## the reachable thing nearest the mouse (`movement.aim_point`) among the objects advertising
## interactions (`kind` `&"object"`, `object` the node), a standing door in reach ahead (`&"door"`,
## measured from the mouse to its leaf, `doors.gap_to`) and a boardable vehicle door (`&"vehicle"`,
## from the mouse to its handle). Two kinds at one gap go to the object, then the door. An
## interaction in progress is `&"end"` (Space stands up) and a ride is `&"vehicle"` (seated, Space
## gets out; on the way in or out it does nothing).
func interact_target() -> Dictionary:
	if character.is_dead:
		return {}
	if _vehicle_use.is_active():
		return { "kind": &"vehicle" }
	if _interaction.is_busy():
		return { "kind": &"end" }
	var aim: Vector2 = character.movement.aim_point
	var best := {}
	var best_gap := INF
	var entry: Dictionary = _interaction.nearest_in_reach()
	if not entry.is_empty():
		best = { "kind": &"object", "object": entry["object"], "entry": entry }
		best_gap = entry["gap"]
	var door: Node2D = doors.door_in_reach()
	var door_gap: float = doors.gap_to(door, aim) if door != null else INF
	if door_gap < best_gap:
		best = { "kind": &"door", "object": door }
		best_gap = door_gap
	if _vehicle_use.nearest_door_distance(aim) < best_gap:
		best = { "kind": &"vehicle" }
	return best


## Space at once: act on `interact_target()`: sit, lie or toggle the object (a random valid action),
## toggle the door (`doors.use`), board by the nearest vehicle door or get out of the vehicle, or
## end the interaction in progress. The human's controller waits for a door's key to be let go
## instead, so a hold can scroll it; an NPC's controller and the test puppet's `use()` call this.
func try_interact() -> void:
	var target := interact_target()
	match target.get("kind", &""):
		&"end":
			_interaction.end_interaction()
		&"object":
			_interaction.begin_random(target["entry"])
			_stand_if_busy()
		&"door":
			doors.use(target["object"])
		&"vehicle":
			_vehicle_use.try_use_vehicle()
			_stand_if_busy()


## The reachable objects and their valid actions, for a controller that wants to choose
## deliberately (an AI). Each entry is `{ object, specs }`; empty when nothing is in reach.
func interactions_in_reach() -> Array:
	return _interaction.interactions_in_reach()


## Begin the action `id` on `object` if it is reachable and valid; true on success. Lets a
## controller pick both the object and the action, unlike the random `try_interact()`.
func interact_with(object: Node, id: String) -> bool:
	if _vehicle_use.is_active():
		return false
	var began: bool = _interaction.interact_with(object, id)
	_stand_if_busy()
	return began


## End the active interaction, if any (explicit stop, vs the `try_interact()` toggle).
func end_interaction() -> void:
	_interaction.end_interaction()


## The active interaction's HUD label, or "" when idle.
func interaction_label() -> String:
	return _interaction.active_label()


## The active object interaction as `{ object, id }` (`id`: `lie`, `sit`, `hide`, ...), empty when
## idle: what a mesh reads to show who lies on a bed (`is_busy` says first whether to ask).
func active_interaction() -> Dictionary:
	return _interaction.active()


## True while locked in an object interaction (sitting, lying, …) or using a vehicle (boarding,
## riding, getting out).
func is_busy() -> bool:
	return _interaction.is_busy() or _vehicle_use.is_active()


## The vehicle the character is boarding, riding in or getting out of; null on foot.
func vehicle() -> Node:
	return _vehicle_use.vehicle()


## True only while seated in a vehicle (not on the way in or out).
func is_in_vehicle() -> bool:
	return _vehicle_use.is_in_vehicle()


## True while the Vehicles domain poses the body for a ride (`set_ride_pose`, until `end_ride`):
## boarding, seated or getting out. The ride's pose wins over the body's own (no hand over the
## eyes).
func is_riding() -> bool:
	return _riding


## The Vehicles domain poses the riding character for this frame: at `at` (world), facing `toward`
## (unit), folded `fold` (0 standing .. 1 seated: the crouch fold, so `movement.posture_folded()`
## reads it), its legs stepping with `step` (px/s, its motion through the vehicle). The first pose
## of a ride puts the held item away and takes the body off the physics layers (the vehicle carries
## it).
func set_ride_pose(at: Vector2, toward: Vector2, fold: float, step := Vector2.ZERO) -> void:
	if not _riding:
		_riding = true
		character.ammo.cancel()
		_shape.set_deferred("disabled", true)
	character.global_position = at
	character.facing = toward.normalized()
	character.movement.aim_point = at + character.facing * 64.0
	character.movement.stand_up()
	character.movement.fold(fold)
	_ride_step = step
	character.anatomy.invalidate_rig()


## The ride is over (out of the vehicle, or never posed): the character stands on its own feet where
## it is, with its body back on the physics layers and its item in hand.
func end_ride() -> void:
	if _riding:
		_riding = false
		_shape.set_deferred("disabled", false)
	_ride_step = Vector2.ZERO
	character.movement.aim_point = character.global_position + character.facing * 64.0
	character.anatomy.invalidate_rig()


## Step the ride, right after the controller: it overrides that frame's intent (it walks the
## character to the door, poses it in and out, and hands its keys on to the vehicle from the
## driver's seat).
func control(delta: float) -> void:
	_vehicle_use.control(delta)


## Hold the body still for this frame when a ride or an interaction has it; true when it did. While
## in an interaction the character is fully frozen: it holds the exact spot the interaction placed
## it (possibly overlapping the object, via a collision exception the interaction sets) and runs no
## movement, aim, knockback or push, which is what keeps a seated body from being ejected or shoving
## its neighbours. A ride's frame only breathes, its legs stepping with the pose's step; its pose
## wins over a stun's look (no hunch, no hand over the eyes), which eases back in once out.
func hold_frame(delta: float) -> bool:
	var movement: CharacterMovement = character.movement
	if _riding:
		movement.run_input = false
		movement.hold(delta)
		character.anatomy.hold(delta, _ride_step, 0.0)
		return true
	if _interaction.is_busy():
		movement.hold(delta)
		character.anatomy.hold(delta, Vector2.ZERO, character.stun.level())
		return true
	return false


## Killed boarding or getting out: the ride ends where the body is (the door left as it is).
func abandon() -> void:
	_vehicle_use.abandon()


## Keep the collision exception with `body` (one the character just left: an interaction's object, a
## vehicle) until the body (its circle plus `CLEAR_MARGIN`) no longer overlaps it, then drop it, so
## restoring the collision never finds an overlap for the solver to eject either out of. A freed
## body is forgotten.
func keep_clear_of(body: Node) -> void:
	if not _clearing.has(body):
		_clearing.append(body)


## Stop waiting to clear `body` (the character is back on or in it, so its exception stays); true
## when it was waiting.
func stop_clearing(body: Node) -> bool:
	if not _clearing.has(body):
		return false
	_clearing.erase(body)
	return true


## Drop the collision exception with each body `keep_clear_of` waits on that the body has cleared
## (once a physics frame, after the move).
func restore_cleared() -> void:
	for i in range(_clearing.size() - 1, -1, -1):
		var body = _clearing[i]  # untyped, as the list
		if not is_instance_valid(body):
			_clearing.remove_at(i)
		elif not _overlaps(body):
			character.remove_collision_exception_with(body)
			TwinSpace.share_space(character, body, false)
			_clearing.remove_at(i)


## An interaction began: stand up for it, whatever the posture was (no cooldown, it is not a
## controller's choice).
func _stand_if_busy() -> void:
	if is_busy():
		character.movement.stand_up()


## Whether the body (its circle plus `CLEAR_MARGIN`, as tall as it stands) overlaps `body`'s 3D body
## in the twin space (interface 29): a piece, a wall or a door, or a vehicle.
func _overlaps(body: Node) -> bool:
	var space := TwinSpace.space_of(character)
	if space == null:
		return false
	var cylinder := CylinderShape3D.new()
	cylinder.radius = (character.radius + CLEAR_MARGIN) * RenderConfig.unit
	cylinder.height = BodyHeights.head_top(character.movement.body_posture()) - CLEAR_FROM
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = cylinder
	params.collision_mask = PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_VEHICLE
	params.transform = Transform3D(
		Basis(), PlanSpace.lift(character.global_position, CLEAR_FROM + cylinder.height * 0.5)
	)
	for result in TwinSpace.intersecting(space, params, CLEAR_HITS):
		if TwinSpace.owner_of(result["collider"]) == body:
			return true
	return false
