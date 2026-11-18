class_name CharacterRise
extends RefCounted
## Character domain, rise to fire (`character.gd`'s `rise`, D7 and D7a, `docs/cover-and-stance.md`
## P6): a ducked character that fires a gun behind cover rises over it and drops back. `pose_needed`
## says which pose its muzzle must rise to: the duck's muzzle line toward the aim is cast into the
## twin space (`TwinSpace`) for `CharacterRiseConfig.reach` from the body's centre; what it meets
## there is the cover (a far obstacle is not), the part it struck gives the cover's height (a
## counter's backsplash is taller than its top) and `BodyHeights.lowest_clearing` the lowest pose
## whose muzzle is over it; the line is cast again from that pose for a taller part behind the
## first, until it is clear. Cover no pose clears (a wardrobe, a wall) answers `BodyHeights.NONE`:
## the body does not rise and its round meets the cover. `rise_to` takes the pose and holds it for
## the dwell; `movement.body_posture()` reports it, so the twin, the zones, the eye and the muzzle
## follow.

## The twin layers a rise looks at: the world and vehicles, not the bodies (a body is no cover).
const MASK := PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_VEHICLE
## How many times the line is cast again from a higher pose: a duck, a fire-over, a standing pose.
const MAX_CASTS := 3

## The ray every ask refills.
static var _ray := PhysicsRayQueryParameters3D.new()

## The character that rises.
var character: CharacterBody2D
## The pose risen to (`BodyHeights.FIRE_OVER` or `STAND`), `BodyHeights.NONE` while ducked.
var _pose: StringName = BodyHeights.NONE
## Seconds until a risen body may fire (it is exposed from the moment it rises), and until it
## drops back to the duck.
var _wait := 0.0
var _dwell := 0.0


## The rise of `host`.
func _init(host: CharacterBody2D) -> void:
	character = host


## The pose risen to, `BodyHeights.NONE` while ducked (or not crouching).
func pose() -> StringName:
	return _pose


## True while a body has risen and is still taking its `rise_time`: its trigger is held back.
func rising() -> bool:
	return _wait > 0.0


## Count the timers down; a body whose dwell is up drops back to the duck.
func tick(delta: float) -> void:
	_wait = maxf(_wait - delta, 0.0)
	if _pose == BodyHeights.NONE:
		return
	_dwell -= delta
	if _dwell <= 0.0:
		drop()


## Duck again: no pose risen to, nothing waited for.
func drop() -> void:
	if _pose != BodyHeights.NONE:
		character.anatomy.invalidate_rig()
	_pose = BodyHeights.NONE
	_wait = 0.0
	_dwell = 0.0


## Rise to `pose` (what `pose_needed` said) and hold it for `CharacterRiseConfig.dwell` after the
## last time this is asked. A pose never lowers a pose already risen to (no flicker mid-burst); one
## it is at or above, `DUCK` or `NONE` only holds the rise it has. A body is exposed as soon as it
## has risen but may fire only once `CharacterRiseConfig.rise_time` has passed: true when it may
## fire now (always for a body that is not crouched or not risen).
func rise_to(wanted: StringName) -> bool:
	if character.movement.posture() != &"crouch":
		return true
	if (wanted != BodyHeights.NONE and wanted != BodyHeights.DUCK
			and BodyHeights.muzzle(wanted) > BodyHeights.muzzle(character.movement.body_posture())):
		_pose = wanted
		_wait = CharacterRiseConfig.rise_time
		character.anatomy.invalidate_rig()
	if _pose != BodyHeights.NONE:
		_dwell = CharacterRiseConfig.dwell
	return _wait <= 0.0


## The pose the character, ducked, must fire its held gun in `hand` from: the lowest whose muzzle
## clears the cover in its line of fire (`BodyHeights.DUCK` for none, `NONE` for cover no pose
## clears). Cover is what the line meets within `reach` of the body; once it has met some, the line
## is judged across the whole of the piece (`cover_depth` further on), so a part behind the first
## (a backsplash) counts. The line ends at the aim point.
func pose_needed(hand: int) -> StringName:
	var space := TwinSpace.space_of(character)
	if space == null:
		return BodyHeights.DUCK
	var weapon: CharacterWeapon = character.weapon
	var direction := weapon.shot_direction(hand)
	var run := maxf(weapon.muzzle_origin(hand).distance_to(weapon.aim_target()), 1.0)
	var length := minf(CharacterRiseConfig.reach, run)
	var needed := BodyHeights.DUCK
	for _cast in MAX_CASTS:
		var found := _cast_from(space, direction, run, length, needed)
		if found.is_empty():
			return needed
		var next := BodyHeights.lowest_clearing(
			TwinShapes.top_of_shape(found["collider"], found["shape"])
		)
		if next == BodyHeights.NONE:
			return BodyHeights.NONE
		if BodyHeights.muzzle(next) <= BodyHeights.muzzle(needed):
			return needed  # what the line met stands under the bore: not cover
		needed = next
		var contact := PlanSpace.plan_of(found["position"]).distance_to(character.global_position)
		length = minf(maxf(length, contact + CharacterRiseConfig.cover_depth), run)
	return needed


## What the muzzle line of `from_pose` meets within `length` px of the body's centre along the plan
## `direction`, `intersect_ray`'s dictionary ({} for a clear line). `run` is the plan distance to
## the aim point the line climbs or falls to.
func _cast_from(
	space: PhysicsDirectSpaceState3D,
	direction: Vector2,
	run: float,
	length: float,
	from_pose: StringName,
) -> Dictionary:
	var level := BodyHeights.muzzle(from_pose)
	var slope: float = (character.weapon.aim_height_from(level) - level) / run
	_ray.from = PlanSpace.lift(character.global_position, level)
	_ray.to = PlanSpace.lift(
		character.global_position + direction * length, maxf(level + slope * length, 0.0)
	)
	_ray.collision_mask = MASK
	return space.intersect_ray(_ray)
