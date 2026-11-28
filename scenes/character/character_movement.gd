class_name CharacterMovement extends RefCounted
## How a character moves (`character.gd`'s `movement`): the intent its controller writes each frame
## (`move_input`, `aim_point`, `run_input`), its posture (stand or crouch) and the drawn body easing
## into it, running and stamina, the knockback it takes from shoves and the slow of the furniture it
## walks into. Each physics frame the character ticks it (`tick`), pulls the controller's intent
## (`pull`) and then walks it (`walk`), or holds it still in an interaction or a ride (`hold`).

## The one shove a walking body gives a pushable piece it slid into.
const CharacterPush = preload("res://scenes/character/character_push.gd")
## `aim_height`'s two answers that name no height: fly level at the muzzle's height, or aim at the
## torso of the body at `aim_point`.
const AIM_LEVEL := -1.0
const AIM_AUTO := -2.0
## `_pace`: neither running nor ran dry, running, ran dry.
const PACE_WALKING := 0
const PACE_RUNNING := 1
const PACE_EXHAUSTED := 2

## The character moving.
var character: Node2D
## The controller child it pulls intent from each frame (any node with a `control(character,
## delta)` method); null for none. Found by the character's `_ready`.
var controller: Node
## Intent, written each frame by the controller.
## Desired move direction (already 0–1 length).
var move_input := Vector2.ZERO
## World point to face.
var aim_point := Vector2.ZERO
## How high the aim is, px above the floor, at `aim_point`: what a shot is aimed at (`AIM_LEVEL`: it
## flies level at the muzzle's height, the player's aim at the floor; `AIM_AUTO`: the centre of the
## torso of whoever stands at `aim_point`, else level, an AI's).
var aim_height := AIM_AUTO
## Wants to run; honoured only while moving with stamina left.
var run_input := false
## Move speed (px/s). Tests and sandboxes set it through `actor(..., props)` as `"movement:speed"`.
var speed := 150.0
## Stamina as a fraction of a full bar; spent while running, regained otherwise.
var stamina := 1.0
## The plan velocity (px/s) the walk was asked for last frame, then what it left after the slide:
## the plan handle's own, no 2D engine moves it. Read by what asks how a body moves by itself.
var velocity := Vector2.ZERO
## `PACE_RUNNING` this frame; `PACE_EXHAUSTED` ran dry and walks until stamina refills to
## `CharacterPaceConfig.run_resume_fraction`.
var _pace := PACE_WALKING
## The body's height: a `CharacterPostureConfig.postures` key (`stand` or `crouch`). A crouch is a
## smaller target and slower; only a standing character can run. Set through `set_posture()`.
var _posture: StringName = &"stand"
## Seconds until the posture may change again (`CharacterPostureConfig.change_time` after each
## change).
var _posture_cooldown := 0.0
## What the body is drawn at, easing toward the posture: its height as a share of a standing one (1
## = standing, down to the crouch row's).
var _posture_height := 1.0
## Knockback velocity from objects shoved into the character; decays each frame. Added on
## top of controller-driven movement.
var _knockback := Vector2.ZERO
## Speed multiplier from pushing objects last frame (1.0 = unencumbered).
var _push_slow := 1.0


## The movement of `host`.
func _init(host: Node2D) -> void:
	character = host


## Pull this frame's intent from the controller, so facing and movement use this frame's input.
func pull(delta: float) -> void:
	if controller:
		controller.control(character, delta)


## Count the posture's cooldown and the rise's timers down and ease the drawn body toward the
## posture (in a vehicle the ride poses the fold instead).
func tick(delta: float) -> void:
	_posture_cooldown = maxf(_posture_cooldown - delta, 0.0)
	character.weapon.rise.tick(delta)
	if not character.use.is_riding():
		_ease_posture(delta)


## One frame on foot: settle the running and the stamina, move and slide at the walk (or run)
## speed plus any knockback and a stun's drift, let the knockback wear off and shove what the body
## slid into (which slows it).
func walk(delta: float) -> void:
	var stun: CharacterStun = character.stun
	_update_stamina(run_input and _posture == &"stand" and stun.level() <= 0.0
			and move_input.length() > CharacterPaceConfig.run_min_input, delta)
	velocity = move_input * _move_speed() * _push_slow + _knockback + stun.drift()
	var lead := TwinSpace.walker_of(character)
	if lead != null:
		# the 3D body walks and the 2D body is written from it (`CharacterTwin`); a body with no
		# twin yet (added this frame) stays where it is
		velocity = lead.walk(velocity)
	else:
		velocity = Vector2.ZERO
	_knockback = _knockback.move_toward(
		Vector2.ZERO,
		CharacterPushConfig.knockback_friction * delta,
	)
	_push_slow = _ease_push_slow(_apply_pushes(lead), delta)


## A frame held still (an interaction, a ride): no movement or input, stamina refilling, and any
## pending shove dropped so moving again doesn't lurch.
func hold(delta: float) -> void:
	move_input = Vector2.ZERO
	velocity = Vector2.ZERO
	_update_stamina(false, delta)
	_knockback = Vector2.ZERO


## Take a shove of `impulse`: divided by the character's mass and folded into locomotion.
func knock(impulse: Vector2) -> void:
	_knockback += impulse / character.get_mass()


## The body's momentum (px/s): the walk plus any shove. A dying body falls with it.
func momentum() -> Vector2:
	return move_input * _move_speed() * _push_slow + _knockback


## Stand, whatever the posture was (no cooldown, it is not a controller's choice): an interaction,
## a ride and death stand the body.
func stand_up() -> void:
	_posture = &"stand"
	character.weapon.rise.drop()


## Draw the body folded `fold` (0 standing .. 1 seated: the crouch fold, so `posture_folded()`
## reads it), at once: a ride's pose, and a dying body (0) falling from the standing skeleton.
func fold(amount: float) -> void:
	_posture_height = lerpf(
		1.0,
		BodyHeights.height_share(BodyHeights.DUCK),
		clampf(amount, 0.0, 1.0),
	)


## Take a posture: `stand` or `crouch` (`CharacterPostureConfig.postures`). True when the character
## is in it afterwards, so asking for the posture it already holds is a harmless `true`: a
## controller can write its wanted posture every frame. Refused (false) while dead, locked in an
## interaction, or within `CharacterPostureConfig.change_time` of the last change. A crouch is
## slower, a smaller target and cannot run.
func set_posture(wanted: StringName) -> bool:
	if wanted == _posture:
		return true
	if (character.is_dead
			or character.use.is_busy()
			or _posture_cooldown > 0.0
			or not CharacterPostureConfig.postures.has(wanted)):
		return false
	if wanted == &"stand" and not has_room_for(BodyHeights.STAND):
		return false  # a taller body would grow into what is over it
	_posture = wanted
	character.weapon.rise.drop()
	_posture_cooldown = CharacterPostureConfig.change_time
	character.anatomy.invalidate_rig()
	return true


## Whether the body, at `pose` (a `BodyHeights` pose), would stand clear of the solids over it: a
## taller cylinder in the twin space is not grown into a shelf, a lintel or a piece lying across it
## (a stand-up or a rise there is refused). True with no twin (nothing to grow into).
func has_room_for(pose: StringName) -> bool:
	var lead := TwinSpace.walker_of(character) as CharacterTwin
	return lead == null or lead.fits(pose)


## C: crouch, or stand back up from a crouch.
func toggle_crouch() -> void:
	set_posture(&"stand" if _posture == &"crouch" else &"crouch")


## The current posture: `stand` or `crouch`.
func posture() -> StringName:
	return _posture


## The posture the body's real height is (`BodyHeights`): a standing body its stature, a crouch the
## duck, a crouch risen over its cover to fire (`character.rise`) the pose it rose to. What its
## twin, a bullet's zone, its eye and its muzzle and a piece of cover's shelter are judged against.
func body_posture() -> StringName:
	if _posture != &"crouch":
		return BodyHeights.STAND
	var risen: StringName = character.weapon.rise.pose()
	return BodyHeights.DUCK if risen == BodyHeights.NONE else risen


## What the body is drawn at right now, easing toward the posture: a standing body's height as a
## share (1 = standing .. the crouch row's). For the rig.
func posture_height() -> float:
	return _posture_height


## How folded the drawn body is, 0 (standing) .. 1 (crouched): the share the rig pitches the spine
## by.
func posture_folded() -> float:
	return clampf(
		(1.0 - _posture_height) / maxf(1.0 - BodyHeights.height_share(BodyHeights.DUCK), 0.01),
		0.0,
		1.0,
	)


## How far further ahead (px) the hands are held at this posture: a crouch holds them out past its
## forward-leaning chest, and so does a stunned hunch (the chest's shift as the spine pitches
## forward by the pose's `hunch()`).
func posture_hand_ahead() -> float:
	var spine: float = ((CharacterBodyConfig.shoulder_height - CharacterBodyConfig.hip_height)
			* character.radius)
	return (CharacterPostureConfig.body_crouch_hand_ahead * posture_folded()
			+ spine * sin(character.anatomy.pose.gait.hunch()) * 0.5)


## True while moving at run speed (asked to run, moving, and not out of stamina).
func is_running() -> bool:
	return _pace == PACE_RUNNING


## Stamina left, 0..1 of a full bar.
func stamina_fraction() -> float:
	return stamina


## The speed (px/s) it would cover ground at running, standing, as it is now (slowed while stunned):
## how a controller works out whether it reaches a place in time.
func run_speed() -> float:
	return _speed_in(&"stand", true)


## The speed (px/s) it would cover ground at walking, standing, as it is now (slowed while stunned
## or weighed down by the outfit): what a controller counts on when it does not run.
func walk_speed() -> float:
	return _speed_in(&"stand", false)


## Walking speed (slower in a lower posture, slowed to `CharacterStunConfig.speed` while stunned
## and by the outfit's weight), or run speed while running (only possible standing and not stunned).
func _move_speed() -> float:
	return _speed_in(_posture, _pace == PACE_RUNNING)


## The speed (px/s) the body covers ground at in posture `which`, running or walking, as it is now
## (stunned or not, and weighed down by what it wears).
func _speed_in(which: StringName, running: bool) -> float:
	return (speed * float(CharacterPostureConfig.postures[which]["speed"])
			* (CharacterPaceConfig.run_speed_mult if running else 1.0)
			* lerpf(1.0, CharacterStunConfig.speed, character.stun.level()) * _weight_speed())


## The kg worn above what the body carries at its tuned speed
## (`CharacterPaceConfig.outfit_free_weight`).
func _extra_weight() -> float:
	return maxf(character.wardrobe.outfit.weight() - CharacterPaceConfig.outfit_free_weight, 0.0)


## The share of its speed the outfit's weight leaves the body (1 = unencumbered).
func _weight_speed() -> float:
	return maxf(
		1.0 - _extra_weight() * CharacterPaceConfig.outfit_speed_per_kg,
		CharacterPaceConfig.outfit_speed_min,
	)


## Ease the drawn body toward the posture (it snaps the last hair, so a settled body stops
## changing).
func _ease_posture(delta: float) -> void:
	var k := 1.0 - exp(-CharacterPostureConfig.posture_ease * delta)
	_posture_height = _eased_to(
		_posture_height,
		BodyHeights.height_share(body_posture()),
		k,
	)


## `now` moved a fraction `k` of the way to `target`, snapped onto it once within a hair of it.
static func _eased_to(now: float, target: float, k: float) -> float:
	var next := lerpf(now, target, k)
	return target if absf(next - target) < 0.002 else next


## Settle this frame's running and spend or regain stamina (a heavier outfit spends it faster).
## Running dry latches `PACE_EXHAUSTED`, which holds until stamina refills to `run_resume_fraction`.
func _update_stamina(wants_run: bool, delta: float) -> void:
	if _pace != PACE_EXHAUSTED:
		_pace = PACE_RUNNING if wants_run and stamina > 0.0 else PACE_WALKING
	if _pace == PACE_RUNNING:
		var strain := 1.0 + _extra_weight() * CharacterPaceConfig.outfit_stamina_per_kg
		stamina = maxf(stamina - delta * strain / CharacterPaceConfig.run_stamina_seconds, 0.0)
		if stamina <= 0.0:
			_pace = PACE_EXHAUSTED
	else:
		stamina = minf(stamina + delta * CharacterPaceConfig.stamina_regen_per_sec, 1.0)
		if _pace == PACE_EXHAUSTED and stamina >= CharacterPaceConfig.run_resume_fraction:
			_pace = PACE_WALKING


## Shove every pushable body the character slid into this frame; return the resulting speed
## multiplier (heavier furniture slows the character more, floored so it never fully locks).
func _apply_pushes(lead: CharacterBody3D) -> float:
	var input_strength := move_input.length()
	if input_strength <= 0.0:
		return 1.0

	var heaviest := 0.0
	for contact in _slides(lead):
		var collider: Object = contact["body"]
		if collider == null or not collider.has_method("apply_impulse"):
			continue
		# The normal points back toward the character, so "into the object" is -normal.
		var dir: Vector2 = -contact["normal"]
		var impulse := (CharacterPushConfig.impulse * input_strength
				* character.get_physics_process_delta_time())
		if not collider.has_method("get_mass"):
			collider.apply_impulse(dir * impulse)
			continue
		# At the point of contact, so a piece pushed off-centre turns; carried, never driven faster
		# than we walk.
		CharacterPush.shove(
			collider,
			dir,
			impulse,
			Vector3(
				contact["at"].x,
				contact["at"].y,
				BodyHeights.contact(&"hip", body_posture()),
			),
			move_input.dot(dir) * _move_speed() * _push_slow,
		)
		heaviest = maxf(heaviest, collider.get_mass())

	if heaviest <= 0.0:
		return 1.0
	return clampf(
		1.0 - heaviest * CharacterPushConfig.slow_per_weight,
		CharacterPushConfig.slow_min,
		1.0,
	)


## What the last walk slid into: `{ body, normal, at }` per contact, the normal (plan) pointing back
## at the character and `at` the plan point. A character walked in the twin space reports what its
## 3D body slid into (the 2D body of each twin); a character with no twin slid into nothing.
func _slides(lead: CharacterBody3D) -> Array[Dictionary]:
	if lead != null:
		return (lead as CharacterTwin).contacts()
	return []


## Slow down at once on contact, but recover toward full speed gradually so losing contact for a
## frame doesn't snap the speed back.
func _ease_push_slow(target: float, delta: float) -> float:
	if target <= _push_slow:
		return target
	return minf(target, _push_slow + CharacterPushConfig.slow_release * delta)
