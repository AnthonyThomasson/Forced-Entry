class_name CharacterMovement extends RefCounted
## How a character moves (`character.gd`'s `movement`): the intent its controller writes each frame
## (`move_input`, `aim_point`, `run_input`), its posture (stand or crouch) and the drawn body easing
## into it, running and stamina, the knockback it takes from shoves and the slow of the furniture it
## walks into. Each physics frame the character ticks it (`tick`), pulls the controller's intent
## (`pull`) and then walks it (`walk`), or holds it still in an interaction or a ride (`hold`).

## The one shove a walking body gives a pushable piece it slid into.
const CharacterPush = preload("res://scenes/character/character_push.gd")

## The character moving.
var character: CharacterBody2D
## The controller child it pulls intent from each frame (any node with a `control(character,
## delta)` method); null for none. Found by the character's `_ready`.
var controller: Node
## Intent, written each frame by the controller.
## Desired move direction (already 0–1 length).
var move_input := Vector2.ZERO
## World point to face.
var aim_point := Vector2.ZERO
## Wants to run; honoured only while moving with stamina left.
var run_input := false
## Move speed (px/s). Tests and sandboxes set it through `actor(..., props)` as `"movement:speed"`.
var speed := 150.0
## Stamina as a fraction of a full bar; spent while running, regained otherwise.
var stamina := 1.0
## Ran dry: walks until stamina refills to `CharacterPaceConfig.run_resume_fraction`.
var _exhausted := false
## Running this frame.
var _running := false
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
func _init(host: CharacterBody2D) -> void:
	character = host


## Pull this frame's intent from the controller, so facing and movement use this frame's input.
func pull(delta: float) -> void:
	if controller:
		controller.control(character, delta)


## Count the posture's cooldown down and ease the drawn body toward the posture (in a vehicle the
## ride poses the fold instead).
func tick(delta: float) -> void:
	_posture_cooldown = maxf(_posture_cooldown - delta, 0.0)
	if not character.use.is_riding():
		_ease_posture(delta)


## One frame on foot: settle the running and the stamina, move and slide at the walk (or run)
## speed plus any knockback and a stun's drift, let the knockback wear off and shove what the body
## slid into (which slows it).
func walk(delta: float) -> void:
	var stun: CharacterStun = character.stun
	_update_stamina(run_input and _posture == &"stand" and stun.level() <= 0.0
			and move_input.length() > CharacterPaceConfig.run_min_input, delta)
	character.velocity = move_input * _move_speed() * _push_slow + _knockback + stun.drift()
	character.move_and_slide()
	_knockback = _knockback.move_toward(
		Vector2.ZERO,
		CharacterPushConfig.knockback_friction * delta,
	)
	_push_slow = _ease_push_slow(_apply_pushes(), delta)


## A frame held still (an interaction, a ride): no movement or input, stamina refilling, and any
## pending shove dropped so moving again doesn't lurch.
func hold(delta: float) -> void:
	move_input = Vector2.ZERO
	character.velocity = Vector2.ZERO
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


## Draw the body folded `fold` (0 standing .. 1 seated: the crouch fold, so `posture_folded()`
## reads it), at once: a ride's pose, and a dying body (0) falling from the standing skeleton.
func fold(amount: float) -> void:
	var crouch_height: float = CharacterPostureConfig.postures[&"crouch"]["height"]
	_posture_height = lerpf(1.0, crouch_height, clampf(amount, 0.0, 1.0))


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
	_posture = wanted
	_posture_cooldown = CharacterPostureConfig.change_time
	character.invalidate_rig()
	return true


## C: crouch, or stand back up from a crouch.
func toggle_crouch() -> void:
	set_posture(&"stand" if _posture == &"crouch" else &"crouch")


## The current posture: `stand` or `crouch`.
func posture() -> StringName:
	return _posture


## The body's height on the coverage scale when in posture `which` (`stand` / `crouch`,
## `CharacterPostureConfig.postures`): what a piece of furniture must stand above to shield it.
## The character's `get_surface()` answers for the posture it is in.
func posture_coverage(which: StringName) -> float:
	return float(CharacterPostureConfig.postures[which]["coverage"])


## What the body is drawn at right now, easing toward the posture: a standing body's height as a
## share (1 = standing .. the crouch row's). For the rig.
func posture_height() -> float:
	return _posture_height


## How folded the drawn body is, 0 (standing) .. 1 (crouched): the share the rig pitches the spine
## by.
func posture_folded() -> float:
	var crouch_height: float = CharacterPostureConfig.postures[&"crouch"]["height"]
	return clampf((1.0 - _posture_height) / maxf(1.0 - crouch_height, 0.01), 0.0, 1.0)


## How far further ahead (px) the hands are held at this posture: a crouch holds them out past its
## forward-leaning chest, and so does a stunned hunch (the chest's shift as the spine pitches
## forward by the pose's `hunch()`).
func posture_hand_ahead() -> float:
	var spine: float = ((CharacterBodyConfig.shoulder_height - CharacterBodyConfig.hip_height)
			* character.radius)
	return (CharacterPostureConfig.body_crouch_hand_ahead * posture_folded()
			+ spine * sin(character.pose.gait.hunch()) * 0.5)


## True while moving at run speed (asked to run, moving, and not out of stamina).
func is_running() -> bool:
	return _running


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
	return _speed_in(_posture, _running)


## The speed (px/s) the body covers ground at in posture `which`, running or walking, as it is now
## (stunned or not, and weighed down by what it wears).
func _speed_in(which: StringName, running: bool) -> float:
	return (speed * float(CharacterPostureConfig.postures[which]["speed"])
			* (CharacterPaceConfig.run_speed_mult if running else 1.0)
			* lerpf(1.0, CharacterStunConfig.speed, character.stun.level()) * _weight_speed())


## The kg worn above what the body carries at its tuned speed
## (`CharacterPaceConfig.outfit_free_weight`).
func _extra_weight() -> float:
	return maxf(character.outfit().weight() - CharacterPaceConfig.outfit_free_weight, 0.0)


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
		float(CharacterPostureConfig.postures[_posture]["height"]),
		k,
	)


## `now` moved a fraction `k` of the way to `target`, snapped onto it once within a hair of it.
static func _eased_to(now: float, target: float, k: float) -> float:
	var next := lerpf(now, target, k)
	return target if absf(next - target) < 0.002 else next


## Settle this frame's running and spend or regain stamina (a heavier outfit spends it faster).
## Running dry latches `_exhausted`, which holds until stamina refills to `run_resume_fraction`.
func _update_stamina(wants_run: bool, delta: float) -> void:
	_running = wants_run and not _exhausted and stamina > 0.0
	if _running:
		var strain := 1.0 + _extra_weight() * CharacterPaceConfig.outfit_stamina_per_kg
		stamina = maxf(stamina - delta * strain / CharacterPaceConfig.run_stamina_seconds, 0.0)
		if stamina <= 0.0:
			_exhausted = true
			_running = false
	else:
		stamina = minf(stamina + delta * CharacterPaceConfig.stamina_regen_per_sec, 1.0)
		if _exhausted and stamina >= CharacterPaceConfig.run_resume_fraction:
			_exhausted = false


## Shove every pushable body the character slid into this frame; return the resulting speed
## multiplier (heavier furniture slows the character more, floored so it never fully locks).
func _apply_pushes() -> float:
	var input_strength := move_input.length()
	if input_strength <= 0.0:
		return 1.0

	var heaviest := 0.0
	for i in character.get_slide_collision_count():
		var collision := character.get_slide_collision(i)
		var collider := collision.get_collider()
		if collider == null or not collider.has_method("apply_impulse"):
			continue
		# The normal points back toward the character, so "into the object" is -normal.
		var dir := -collision.get_normal()
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
			collision.get_position(),
			move_input.dot(dir) * _move_speed(),
		)
		heaviest = maxf(heaviest, collider.get_mass())

	if heaviest <= 0.0:
		return 1.0
	return clampf(
		1.0 - heaviest * CharacterPushConfig.slow_per_weight,
		CharacterPushConfig.slow_min,
		1.0,
	)


## Slow down at once on contact, but recover toward full speed gradually so losing contact for a
## frame doesn't snap the speed back.
func _ease_push_slow(target: float, delta: float) -> float:
	if target <= _push_slow:
		return target
	return minf(target, _push_slow + CharacterPushConfig.slow_release * delta)
