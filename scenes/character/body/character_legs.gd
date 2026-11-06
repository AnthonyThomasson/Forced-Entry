extends RefCounted
## Character LEGS (Character domain, animate layer): the legs' contact with the world. The rig
## strides, folds and trails the feet wherever the pose puts them, which can be well past the body's
## collision circle (a stride's toes, a crouch's leading knees), so this layer, stepped by
## character.gd each physics frame after the pose, finds where each leg would stop and keeps the
## drawn leg there:
## - each ankle is swept from the body centre toward where the rig would put it (a foot-sized
##   circle, like the hands, `body_sweep.gd`) and rests at the first wall or solid piece it meets,
##   sliding the leftover along the surface; the rig reads it back through
##   `character.anatomy.legs.ankle(i)`;
## - the knee is judged the same way from the leg the ankle leaves: a knee that would pass through
##   something moves the foot back by what it overshot (a crouch facing a wall keeps its knees off
##   it), up to `KNEE_TRIES`;
## - a foot or knee swinging into a light, pushable piece shoves it where it rests, scaled by how
##   fast the foot is moving into it and how far it wanted to go, and capped so the piece is never
##   driven faster than the character walks (the body's own push, `character_push.gd`). A fixed wall
##   only stops the leg, and a foot at rest pushes nothing.
## Other characters are solid to a leg (it rests against them) but are never shoved by it. Nothing
## is cast while nothing is near. Tuning: CharacterPushConfig.leg_*.

const Rig = preload("res://scenes/character/body/character_rig.gd")
## The shared near-solid gate and reused queries (typed here by its script).
const Sweep = preload("res://scenes/character/body/body_sweep.gd")
## The shove the body's own walking push gives (at the contact point, carried at walking pace).
const Push = preload("res://scenes/character/character_push.gd")
## Nothing is cast unless something solid lies within this many px of the body centre (a leg reaches
## ~55).
const NEAR := 72.0
## How many times a knee that would pass through something may move its foot back.
const KNEE_TRIES := 3
## A foot this far (px) short of where it wanted to go is resting against something.
const REST_EPS := 0.5
## Px a foot must have wanted to go past the obstacle for its shove to be at full strength.
const FULL_PRESS := 6.0

## Per side: where the ankle rests (local x/y px), or null when nothing stops it.
var _ankle: Array = [null, null]
## Per side, ankle then knee: where each was wanted last frame (local px), for its speed.
var _prev: Array = [null, null, null, null]
## The character-owned shared near-solid gate and reused sweep queries.
var sweep: Sweep


## Where side `i`'s ankle rests (local x/y), or null when nothing is in its way.
func ankle(i: int) -> Variant:
	return _ankle[i]


## Forget every contact (the character is locked in an interaction, or has died).
func clear() -> void:
	_ankle = [null, null]
	_prev = [null, null, null, null]


## Rest both legs of `character` against what is near and shove what a foot swings into.
func update(character: CharacterBody2D, delta: float) -> void:
	if sweep.gate_enabled and not sweep.near_solid:
		clear()
		return
	var rig := Rig.new(character, false)
	for i in 2:
		_ankle[i] = _rest_leg(character, rig, i, delta)


## Side `i`'s resting ankle (local x/y), or null when neither it nor the knee meets anything.
func _rest_leg(
	character: CharacterBody2D,
	rig: Rig,
	i: int,
	delta: float,
) -> Variant:
	var wanted: Vector3 = rig.point(Rig.ANKLE[i])
	var ankle_at := Vector2(wanted.x, wanted.y)
	var rested := _sweep(character, ankle_at)
	var knee_wanted := Vector2.ZERO
	var knee_rested := Vector2.ZERO
	for _try in KNEE_TRIES:
		var knee3: Vector3 = rig.knee_at(i, Vector3(rested.x, rested.y, wanted.z))
		knee_wanted = Vector2(knee3.x, knee3.y)
		knee_rested = _sweep(character, knee_wanted)
		var overshoot := knee_rested - knee_wanted
		if overshoot.length() <= REST_EPS:
			break
		# The knee would pass through something: step the foot back by how far it overshot, then
		# rest it again.
		rested = _sweep(character, rested + overshoot)
	_press(character, 2 + i, knee_wanted, knee_rested, delta)
	_press(character, i, ankle_at, rested, delta)
	if (rested.distance_to(ankle_at) <= REST_EPS
			and knee_rested.distance_to(knee_wanted) <= REST_EPS):
		return null
	return rested


## The place `target` (local px) can be reached from the body centre by a foot-sized circle:
## `target` itself when the way is clear, else where it first touches a wall or solid piece, slid
## along the surface for what is left.
func _sweep(character: CharacterBody2D, target: Vector2) -> Vector2:
	return sweep.circle(character.global_position, target, CharacterPushConfig.leg_radius)


## Shove the light piece (if any) that a point wanted at `wanted` but rested at `rested` (local px)
## is pressing into. `slot` indexes `_prev`: how fast the point is moving, in the world, into the
## piece sets the strength.
func _press(
	character: CharacterBody2D,
	slot: int,
	wanted: Vector2,
	rested: Vector2,
	delta: float,
) -> void:
	var previous = _prev[slot]
	_prev[slot] = wanted
	var into := wanted - rested
	var depth := into.length()
	if previous == null or depth <= REST_EPS or delta <= 0.0:
		return
	var dir := into / depth
	var velocity: Vector2 = (wanted - (previous as Vector2)) / delta + character.get_real_velocity()
	var approach := velocity.dot(dir)
	if approach <= 0.0:
		return
	var at: Vector2 = character.global_position + rested
	var piece: Node = sweep.pushable_at(at)
	if piece == null:
		return
	var strength := (clampf(approach / maxf(float(character.movement.speed), 1.0), 0.0, 1.0)
			* clampf(depth / FULL_PRESS, 0.0, 1.0))
	# At the point where the leg rests, so a piece pressed near an end turns; never driven faster
	# than the character walks.
	Push.shove(
		piece,
		dir,
		CharacterPushConfig.leg_push_impulse * strength * delta,
		at,
		float(character.movement.speed),
	)
