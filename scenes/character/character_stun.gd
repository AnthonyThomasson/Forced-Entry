class_name CharacterStun extends RefCounted
## A grenade's flash and bang on a character (`character.gd`'s `stun`; docs/grenades.md G13): the
## seconds left blind and deaf, the blind seconds at the burst, and the clock and phases a stunned
## character's aim sways and its walk drifts by while it lasts. The character takes a stun through
## `take_stun` (an explosion's hook, interface 3), counts it down each physics frame (`update`) and
## clears it on death. Tuning: CharacterStunConfig.

## The character the stun is on.
var character: CharacterBody2D
## Seconds left blind.
var _blind_left := 0.0
## The blind seconds at the burst.
var _blind_total := 0.0
## Seconds left deaf.
var _deaf_left := 0.0
## Seconds since the stun began: the clock the aim sways and the walk drifts by.
var _clock := 0.0
## The sway's and the drift's phases, drawn at each new stun.
var _phase := Vector2.ZERO


## The stun of `host`.
func _init(host: CharacterBody2D) -> void:
	character = host


## Blind and deafen the character for `blind` and `deaf` seconds (a grenade's burst). A new stun
## takes the longer of the old and the new timers, blind and deaf each, and posts `&"stun"`
## `{ character, position, blind, deaf }`. While either lasts the character is disoriented
## (`level()`): slowed, drifting, unable to run and its aim swaying. A stun that is neither does
## nothing; a dead character cannot be stunned.
func take(blind: float, deaf: float) -> void:
	if character.is_dead or (blind <= 0.0 and deaf <= 0.0):
		return
	if level() <= 0.0:
		_clock = 0.0
		_phase = Vector2(randf() * TAU, randf() * TAU)
	if blind > _blind_left:
		_blind_left = blind
		_blind_total = blind
	_deaf_left = maxf(_deaf_left, deaf)
	EventBus.post(
		&"stun",
		{ "character": character, "position": character.global_position, "blind": blind,
			"deaf": deaf },
	)


## True while flash-blinded.
func is_blind() -> bool:
	return _blind_left > 0.0


## True while deafened.
func is_deaf() -> bool:
	return _deaf_left > 0.0


## How disoriented the character is, 0 (not at all) .. 1 (fully): full while the longer of the blind
## and deaf times has more than `CharacterStunConfig.recover_tail` seconds to run, then falling
## linearly to 0 over that tail.
func level() -> float:
	return clampf(
		maxf(_blind_left, _deaf_left) / maxf(CharacterStunConfig.recover_tail, 0.01),
		0.0,
		1.0,
	)


## What a stun looks like from outside, for the UI: `{ blind, blind_total, deaf, level }` (seconds
## left blind and deaf, the blind seconds at the burst, the disorientation 0..1).
func view() -> Dictionary:
	return {
		"blind": _blind_left,
		"blind_total": _blind_total,
		"deaf": _deaf_left,
		"level": level(),
	}


## Count the stun down by `delta`.
func update(delta: float) -> void:
	if _blind_left <= 0.0 and _deaf_left <= 0.0:
		return
	_clock += delta
	_blind_left = maxf(_blind_left - delta, 0.0)
	_deaf_left = maxf(_deaf_left - delta, 0.0)


## A slow wandering value in -1..1 that a stunned character's aim and walk follow (two out-of-step
## sines), `offset` out of step with the others.
func wander(offset: float) -> float:
	return (0.6 * sin(_clock * 1.1 + _phase.x + offset)
			+ 0.4 * sin(_clock * 2.3 + _phase.y + offset))


## The sideways drift (px/s) of a stunned walk: across the way the character is walking, wandering
## with the stun.
func drift() -> Vector2:
	var at := level()
	var move: Vector2 = character.move_input
	if at <= 0.0 or move.length_squared() < 0.0001:
		return Vector2.ZERO
	return move.orthogonal().normalized() * CharacterStunConfig.drift * at * wander(1.7)


## End the stun at once: a dead body sees and hears nothing more to fade.
func clear() -> void:
	_blind_left = 0.0
	_deaf_left = 0.0
